import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/app_constants.dart';
import 'supabase_service.dart';

class PoolDailyConfig {
  final String poolId;
  final String slotStrategy;
  final int? maxBookingsPerDay;

  const PoolDailyConfig({
    required this.poolId,
    required this.slotStrategy,
    this.maxBookingsPerDay,
  });

  bool get hasWindowStrategy =>
      slotStrategy == 'site_window' || slotStrategy == 'pool_window';
}

class BookingAvailabilityService {
  final SupabaseClient supabase;

  BookingAvailabilityService(this.supabase);

  // ------------------------------------------------------------
  // ALLOWED POOLS
  // ------------------------------------------------------------

  Future<Set<String>> allowedPools({
    required int customerId,
    required int siteId,
    required String loadType,
  }) async {
    final rows = await withRetry(() => supabase
        .from('eligible_capacity_pools')
        .select('pool_id')
        .eq('customer_id', customerId)
        .eq('site_id', siteId)
        .eq('is_allowed', true)
        .eq('load_type', loadType));

    final pools =
        rows.map((r) => r['pool_id'].toString()).toSet();
    return pools;
  }

  // ------------------------------------------------------------
  // RAW AVAILABILITY ROWS
  // ------------------------------------------------------------

  Future<List<Map<String, dynamic>>> availabilityRows({
    required int siteId,
    required DateTime from,
    required DateTime to,
  }) async {
    final fromIso = from.toIso8601String();
    final toIso = to.toIso8601String();

    final response = await withRetry(() => supabase
      .from('slot_availability_projection')
      .select('pool_id, slot_start, slot_status, visible')
      .eq('site_id', siteId)
      .gte('slot_start', fromIso)
      .lt('slot_start', toIso)
      .order('slot_start', ascending: true)
      .range(0, AppConstants.maxSlotQueryLimit));

    final result = List<Map<String, dynamic>>.from(response).map((r) {
      return {
        'pool_id': r['pool_id'].toString(),
        'slot_start': r['slot_start'],
        'slot_status': r['slot_status'],
        'visible': r['visible'],
      };
    }).toList();

    assert(result.length < AppConstants.maxSlotQueryLimit,
        'Slot query hit the limit — review maxSlotQueryLimit in AppConstants');

    return result;
  }

  // ------------------------------------------------------------
  // POOL DAILY CONFIGS
  // ------------------------------------------------------------

  Future<Map<String, PoolDailyConfig>> fetchPoolConfigs(
    Set<String> poolIds,
  ) async {
    if (poolIds.isEmpty) return {};

    final rows = await withRetry(() => supabase
        .from('capacity_pools')
        .select('pool_id, slot_strategy, max_bookings_per_day')
        .inFilter('pool_id', poolIds.toList()));

    final configs = <String, PoolDailyConfig>{};
    for (final r in rows) {
      final poolId = r['pool_id'].toString();
      configs[poolId] = PoolDailyConfig(
        poolId: poolId,
        slotStrategy: (r['slot_strategy'] as String?) ?? '',
        maxBookingsPerDay: r['max_bookings_per_day'] as int?,
      );
    }
    return configs;
  }

  // ------------------------------------------------------------
  // DAILY BOOKING COUNTS
  // Counts non-cancelled, non-draft bookings per pool per day.
  // Used to enforce max_bookings_per_day on window-strategy pools.
  // Returns: poolId → day → count
  // ------------------------------------------------------------

  Future<Map<String, Map<DateTime, int>>> fetchDailyBookingCounts({
    required Set<String> poolIds,
    required DateTime from,
    required DateTime to,
  }) async {
    if (poolIds.isEmpty) return {};

    final rows = await withRetry(() => supabase
        .from('bookings')
        .select('pool_id, booking_date')
        .inFilter('pool_id', poolIds.toList())
        .neq('status', 'cancelled')
        .neq('status', 'draft')
        .gte('booking_date', from.toIso8601String())
        .lt('booking_date', to.toIso8601String()));

    final counts = <String, Map<DateTime, int>>{};
    for (final r in rows) {
      final poolId = r['pool_id']?.toString();
      final rawDate = r['booking_date'];
      if (poolId == null || rawDate == null) continue;
      final date = DateTime.parse(rawDate.toString());
      final day = DateTime(date.year, date.month, date.day);
      counts.putIfAbsent(poolId, () => {})[day] =
          (counts[poolId]![day] ?? 0) + 1;
    }
    return counts;
  }

  // ------------------------------------------------------------
  // COMPUTE BOOKABLE DAYS
  // ------------------------------------------------------------

  Set<DateTime> computeBookableDates({
    required List<Map<String, dynamic>> rows,
    required Set<String> allowedPools,
    required int requiredSlots,
    Map<String, PoolDailyConfig> poolConfigs = const {},
    Map<String, Map<DateTime, int>> dailyBookingCounts = const {},
  }) {
    final DateTime minAllowed =
        DateTime.now().add(AppConstants.minAdvanceBooking);

    final Set<DateTime> bookableDates = {};
    final Map<DateTime, Map<String, List<DateTime>>> byDay = {};

    // GROUP ROWS

    for (final r in rows) {
      if (r['slot_status'] != 'available') continue;

      final poolId = r['pool_id'].toString();
      if (!allowedPools.contains(poolId)) continue;

      final DateTime start =
          DateTime.parse(r['slot_start']);

      final DateTime day =
          DateTime(start.year, start.month, start.day);

      byDay
          .putIfAbsent(day, () => {})
          .putIfAbsent(poolId, () => [])
          .add(start);
    }

    // EVALUATE EACH DAY

    for (final entry in byDay.entries) {
      final DateTime day = entry.key;
      bool dayBookable = false;

      for (final poolEntry in entry.value.entries) {
        final poolId = poolEntry.key;
        final List<DateTime> originalSlots = poolEntry.value;

        // Apply max_bookings_per_day for site_window / pool_window pools
        final config = poolConfigs[poolId];
        if (config != null &&
            config.hasWindowStrategy &&
            config.maxBookingsPerDay != null) {
          final dayCount = (dailyBookingCounts[poolId] ?? {})[day] ?? 0;
          if (dayCount >= config.maxBookingsPerDay!) continue;
        }

        if (originalSlots.length < requiredSlots) continue;

        final List<DateTime> slots =
            List<DateTime>.from(originalSlots)..sort();

        int run = 0;
        DateTime? lastTime;

        for (final DateTime time in slots) {
          if (time.isBefore(minAllowed)) {
            run = 0;
            lastTime = null;
            continue;
          }

          if (lastTime == null ||
              time.difference(lastTime).inMinutes != AppConstants.slotDurationMinutes) {
            run = 1;
          } else {
            run++;
          }

          lastTime = time;

          if (run >= requiredSlots) {
            dayBookable = true;
            break;
          }
        }

        if (dayBookable) break;
      }

      if (dayBookable) {
        bookableDates.add(day);
      }
    }
    return bookableDates;
  }

  // ------------------------------------------------------------
  // COMPUTE START TIMES
  // Returns a map of valid start time → pool_id that provides it.
  // When a time is available in multiple pools the first pool
  // processed wins (putIfAbsent). Derive the sorted list from
  // the map's keys in the caller.
  // ------------------------------------------------------------

  Map<DateTime, String> computeStartTimes({
    required List<Map<String, dynamic>> rows,
    required Set<String> allowedPools,
    required int requiredSlots,
  }) {
    final Map<String, List<DateTime>> byPool = {};

    for (final r in rows) {
      if (r['slot_status'] != 'available') continue;

      final poolId = r['pool_id'].toString();
      if (!allowedPools.contains(poolId)) continue;

      final DateTime start = DateTime.parse(r['slot_start']);
      byPool.putIfAbsent(poolId, () => []).add(start);
    }

    final Map<DateTime, String> startPoolMap = {};

    for (final poolEntry in byPool.entries) {
      final poolId = poolEntry.key;
      final List<DateTime> originalSlots = poolEntry.value;
      if (originalSlots.length < requiredSlots) continue;

      final List<DateTime> slots =
          List<DateTime>.from(originalSlots)..sort();

      List<DateTime> run = [];

      for (final DateTime s in slots) {
        if (run.isEmpty || s.difference(run.last) == AppConstants.slotDuration) {
          run.add(s);
        } else {
          _recordStarts(run, requiredSlots, poolId, startPoolMap);
          run = [s];
        }
      }

      _recordStarts(run, requiredSlots, poolId, startPoolMap);
    }

    return startPoolMap;
  }

  void _recordStarts(
    List<DateTime> run,
    int required,
    String poolId,
    Map<DateTime, String> out,
  ) {
    if (run.length < required) return;
    for (int i = 0; i <= run.length - required; i++) {
      out.putIfAbsent(run[i], () => poolId);
    }
  }
}