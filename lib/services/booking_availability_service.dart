import 'package:supabase_flutter/supabase_flutter.dart';

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
    final rows = await supabase
        .from('eligible_capacity_pools')
        .select('pool_id')
        .eq('customer_id', customerId)
        .eq('site_id', siteId)
        .eq('is_allowed', true)
        .eq('load_type', loadType);

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

    final response = await supabase
      .from('slot_availability_projection')
      .select('pool_id, slot_start, slot_status, visible')
      .eq('site_id', siteId)
      .gte('slot_start', fromIso)
      .lt('slot_start', toIso)
      .order('slot_start', ascending: true)
      .range(0, 5000);

    return List<Map<String, dynamic>>.from(response).map((r) {
      return {
        'pool_id': r['pool_id'].toString(),
        'slot_start': r['slot_start'],
        'slot_status': r['slot_status'],
        'visible': r['visible'],
      };
    }).toList();
  }

  // ------------------------------------------------------------
  // COMPUTE BOOKABLE DAYS
  // ------------------------------------------------------------

  Set<DateTime> computeBookableDates({
    required List<Map<String, dynamic>> rows,
    required Set<String> allowedPools,
    required int requiredSlots,
  }) {
    final DateTime minAllowed =
        DateTime.now().add(const Duration(hours: 24));

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
        final List<DateTime> originalSlots = poolEntry.value;

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
              time.difference(lastTime).inMinutes != 30) {
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
  // ------------------------------------------------------------

  List<DateTime> computeStartTimes({
    required List<Map<String, dynamic>> rows,
    required Set<String> allowedPools,
    required int requiredSlots,
  }) {
    final Map<String, List<DateTime>> byPool = {};

    for (final r in rows) {
      if (r['slot_status'] != 'available') continue;

      final poolId = r['pool_id'].toString();
      if (!allowedPools.contains(poolId)) continue;

      final DateTime start =
          DateTime.parse(r['slot_start']);

      byPool.putIfAbsent(poolId, () => []);
      byPool[poolId]!.add(start);
    }

    final Set<DateTime> starts = {};

    for (final poolEntry in byPool.entries) {
      final List<DateTime> originalSlots = poolEntry.value;
      if (originalSlots.length < requiredSlots) continue;

      final List<DateTime> slots =
          List<DateTime>.from(originalSlots)..sort();

      List<DateTime> run = [];

      for (final DateTime s in slots) {
        if (run.isEmpty ||
            s.difference(run.last) ==
                const Duration(minutes: 30)) {
          run.add(s);
        } else {
          _extractStarts(run, requiredSlots, starts);
          run = [s];
        }
      }

      _extractStarts(run, requiredSlots, starts);
    }

    final result = starts.toList()..sort();
    return result;
  }

  void _extractStarts(
    List<DateTime> run,
    int required,
    Set<DateTime> out,
  ) {
    if (run.length < required) return;

    for (int i = 0; i <= run.length - required; i++) {
      out.add(run[i]);
    }
  }
}