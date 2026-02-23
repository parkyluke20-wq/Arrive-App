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

    final pools = rows.map((r) => r['pool_id'].toString()).toSet();

    return pools;
  }

  // ------------------------------------------------------------
  // RAW AVAILABILITY ROWS
  // ------------------------------------------------------------

  Future<List<Map<String, dynamic>>> availabilityRows({
    required int siteId,
    required DateTime from,
    required DateTime to,
  }) {
    return supabase
        .from('time_slot_availability')
        .select('pool_id, slot_start, slot_status')
        .eq('site_id', siteId)
        .gte('slot_start', from)
        .lt('slot_start', to);
  }

  // ------------------------------------------------------------
  // COMPUTE BOOKABLE DAYS
  // ------------------------------------------------------------

  Set<DateTime> computeBookableDates({
    required List<Map<String, dynamic>> rows,
    required Set<String> allowedPools,
    required int requiredSlots,
  }) {

    // 🔒 Rolling 24-hour rule
    final DateTime minAllowed =
        DateTime.now().toUtc().add(const Duration(hours: 24));

    final Set<DateTime> bookableDates = {};

    /// day (UTC midnight) → pool → slots
    final Map<DateTime, Map<String, List<Map<String, dynamic>>>> byDay = {};

    // -------- GROUP ROWS --------

    for (final r in rows) {
      final poolId = r['pool_id'].toString();
      if (!allowedPools.contains(poolId)) continue;

      final DateTime start =
          DateTime.parse(r['slot_start']).toUtc();

      final DateTime day =
          DateTime.utc(start.year, start.month, start.day);

      final bool isAvailable =
          r['slot_status'] == 'available';

      byDay
          .putIfAbsent(day, () => {})
          .putIfAbsent(poolId, () => [])
          .add({
            'time': start,
            'available': isAvailable,
          });
    }

    // -------- EVALUATE EACH DAY --------

    for (final entry in byDay.entries) {
      final day = entry.key;
      bool dayBookable = false;

      for (final poolEntry in entry.value.entries) {
        final poolId = poolEntry.key;
        final slots = poolEntry.value;

        if (slots.isEmpty) continue;

        slots.sort(
          (a, b) =>
              (a['time'] as DateTime)
                  .compareTo(b['time'] as DateTime),
        );

        int run = 0;
        DateTime? lastTime;

        for (final slot in slots) {
          final DateTime time =
              slot['time'] as DateTime;

          final bool ok =
              slot['available'] == true &&
              !time.isBefore(minAllowed);

          if (!ok) {
            run = 0;
            lastTime = null;
            continue;
          }

          if (lastTime == null ||
              time.difference(lastTime) !=
                  const Duration(minutes: 30)) {
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
      } else {
      }
    }

    for (final d in bookableDates.toList()..sort()) {
    }

    return bookableDates;
  }

  // ------------------------------------------------------------
  // START TIMES (UNCHANGED, BUT LOGGED)
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

      final DateTime start = DateTime.parse(r['slot_start']).toUtc();

      byPool.putIfAbsent(poolId, () => []);
      byPool[poolId]!.add(start);
    }

    final Set<DateTime> starts = {};

    for (final poolEntry in byPool.entries) {
      final slots = poolEntry.value;
      if (slots.length < requiredSlots) continue;

      slots.sort();
      List<DateTime> run = [];

      for (final s in slots) {
        if (run.isEmpty ||
            s.difference(run.last) == const Duration(minutes: 30)) {
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
