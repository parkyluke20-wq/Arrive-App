import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/booking_availability_service.dart';

/// NOTE:
/// This controller intentionally does NOT import booking_form_page.dart
/// to avoid circular dependencies.
/// VehicleTypeOption is passed in from the UI layer.
class BookingController extends ChangeNotifier {
  final SupabaseClient supabase;
  final BookingAvailabilityService availabilityService;

  BookingController({
    required this.supabase,
  }) : availabilityService = BookingAvailabilityService(supabase);

  // ---------------- STATE ----------------
  bool _isHydrating = false;
  int? selectedCustomer;
  int? selectedSite;

  /// Vehicle type object is owned by the UI layer.
  /// Controller treats it as an opaque value with known fields.
  dynamic selectedVehicleType;

  DateTime? selectedDate;
  DateTime? selectedStartTime;

  final Set<DateTime> bookableDates = {};
  final List<DateTime> availableStartTimes = [];
  final Map<int, Map<String, bool>> _slotVisibilityByPool = {};
  Set<String> _currentEligiblePools = {};

  bool computingDates = false;
  bool computingTimes = false;
  int _dateComputeVersion = 0;
  int _timeComputeVersion = 0;

  // ---------------- INTENT METHODS ----------------

  Future<void> selectCustomer(int? customerId) async {
    selectedCustomer = customerId;
    selectedSite = null;
    selectedVehicleType = null;
    _clearDateAndTime();
    notifyListeners();
  }

  Future<void> selectSite(int? siteId) async {
    selectedSite = siteId;
    _clearDateAndTime();
    notifyListeners();
  }

  Future<void> selectVehicleType(dynamic vehicleType) async {
    selectedVehicleType = vehicleType;
    _clearDateAndTime();
    notifyListeners();
  }

  Future<void> pickDate(DateTime date) async {
    selectedDate = date;
    selectedStartTime = null;
    availableStartTimes.clear();
    notifyListeners();

    await computeStartTimes();
  }

  void selectStartTime(DateTime? time) {
    selectedStartTime = time;
    notifyListeners();
  }

  // ---------------- AVAILABILITY ----------------

  Future<void> computeBookableDates() async {
    if (_isHydrating) return;
    if (supabase.auth.currentSession == null) {
      return;
    }
    if (selectedCustomer == null ||
        selectedSite == null ||
        selectedVehicleType == null) {
      return;
    }

    final int requestVersion = ++_dateComputeVersion;

    computingDates = true;
    bookableDates.clear();
    notifyListeners();

    final pools = await availabilityService.allowedPools(
      customerId: selectedCustomer!,
      siteId: selectedSite!,
      loadType: selectedVehicleType.loadType,
    );

    if (pools.isEmpty) {
      if (requestVersion != _dateComputeVersion) return;
      computingDates = false;
      notifyListeners();
      return;
    }

    final nowLocal = DateTime.now();

    final startOfToday =
      DateTime(nowLocal.year, nowLocal.month, nowLocal.day);

    final from = startOfToday.subtract(const Duration(days: 1));
    final to = startOfToday.add(const Duration(days: 60));
    final rows = await availabilityService.availabilityRows(
      siteId: selectedSite!,
      from: from,
      to: to,
    );

    _slotVisibilityByPool.clear();
    for (final r in rows) {
      final start = DateTime.parse(r['slot_start']);
      final key = start.millisecondsSinceEpoch;
      final poolId = r['pool_id'] as String;
      final visible = r['visible'] == true;

      _slotVisibilityByPool.putIfAbsent(key, () => {});
      _slotVisibilityByPool[key]![poolId] = visible;
    }

    final result = availabilityService.computeBookableDates(
      rows: rows,
      allowedPools: pools,
      requiredSlots: selectedVehicleType.slotUnitsRequired,
    );

    // 🔒 IMPORTANT: Ignore stale responses
    if (requestVersion != _dateComputeVersion) {
      return;
    }

    bookableDates
      ..clear()
      ..addAll(result);

    computingDates = false;
    notifyListeners();
  }

  Future<void> computeStartTimes() async {
    if (_isHydrating) return;
    if (selectedCustomer == null ||
        selectedSite == null ||
        selectedVehicleType == null ||
        selectedDate == null) {
      return;
    }

    final int requestVersion = ++_timeComputeVersion;

    computingTimes = true;
    availableStartTimes.clear();
    notifyListeners();

    final pools = await availabilityService.allowedPools(
      customerId: selectedCustomer!,
      siteId: selectedSite!,
      loadType: selectedVehicleType.loadType,
    );

    if (pools.isEmpty) {
      if (requestVersion != _timeComputeVersion) return;
      computingTimes = false;
      notifyListeners();
      return;
    }

    _currentEligiblePools = pools;

    final from = DateTime(
      selectedDate!.year,
      selectedDate!.month,
      selectedDate!.day,
    );

    final to = from.add(const Duration(days: 1));

    final rows = await availabilityService.availabilityRows(
      siteId: selectedSite!,
      from: from,
      to: to,
    );

    _slotVisibilityByPool.clear();

    for (final r in rows) {
      final start = DateTime.parse(r['slot_start']);
      final key = start.millisecondsSinceEpoch;
      final poolId = r['pool_id'] as String;
      final visible = r['visible'] == true;

      _slotVisibilityByPool.putIfAbsent(key, () => {});
      _slotVisibilityByPool[key]![poolId] = visible;
    }


    final result = availabilityService.computeStartTimes(
      rows: rows,
      allowedPools: pools,
      requiredSlots: selectedVehicleType.slotUnitsRequired,
    );

    if (requestVersion != _timeComputeVersion) {
      return;
    }

    availableStartTimes
      ..clear()
      ..addAll(result);

    if (selectedStartTime != null &&
        !availableStartTimes.contains(selectedStartTime)) {
      availableStartTimes.insert(0, selectedStartTime!);
    }
    computingTimes = false;
    notifyListeners();
  }

  Future<HydratedBookingResult> hydrateForEdit({
    required String bookingId,
    required List<dynamic> vehicleTypes,
  }) async {
    try {
      final row = await supabase
          .from('bookings')
          .select(
            'booking_id, customer_id, site_id, vehicle_type_id, start_time, '
            'end_time, reference, carrier, vehicle_reg, container_number, '
            'qty_pallets, qty_cases, booking_date, status'
          )
          .eq('booking_id', bookingId)
          .single();

      if (row['status'] == 'cancelled') {
        return HydratedBookingResult.invalidDate(booking: row);
      }

      selectedCustomer = row['customer_id'];
      selectedSite = row['site_id'];

      selectedVehicleType = vehicleTypes.firstWhere(
        (v) => v.vehicleTypeId == row['vehicle_type_id'],
      );

      final DateTime storedStart =
        DateTime.parse(row['start_time']);

      selectedDate = DateTime(
        storedStart.year,
        storedStart.month,
        storedStart.day,
      );

      selectedStartTime = storedStart;

      notifyListeners();
      _isHydrating = false;

      return HydratedBookingResult.success(
        restoredDate: selectedDate!,
        restoredStartTime: selectedStartTime!,
        booking: row,
      );
    } catch (e) {
      _isHydrating = false;
      return HydratedBookingResult.invalidDate();
    }
  }

  // ---------------- HELPERS ----------------

  void _clearDateAndTime() {
    selectedDate = null;
    selectedStartTime = null;
    availableStartTimes.clear();
  }

  bool isSlotVisible(DateTime t) {
    final key = t.millisecondsSinceEpoch;
    final poolMap = _slotVisibilityByPool[key];
    if (poolMap == null) return false;

    for (final poolId in _currentEligiblePools) {
      if (poolMap[poolId] == true) {
        return true; // ANY eligible pool true wins
      }
    }

    return false;
  }

  void clearSelectedDateAndTime() {
    _clearDateAndTime();
    notifyListeners();
  }
}

// ---------------- RESULT MODEL ----------------

class HydratedBookingResult {
  final bool success;
  final DateTime? restoredDate;
  final DateTime? restoredStartTime;
  final Map<String, dynamic>? booking; // <-- added
  final String? reason;

  HydratedBookingResult._(
    this.success,
    this.restoredDate,
    this.restoredStartTime,
    this.booking,
    this.reason,
  );

  factory HydratedBookingResult.success({
    required DateTime restoredDate,
    required DateTime restoredStartTime,
    required Map<String, dynamic> booking, // <-- added
  }) =>
      HydratedBookingResult._(
        true,
        restoredDate,
        restoredStartTime,
        booking,
        null,
      );

  factory HydratedBookingResult.invalidDate({
    Map<String, dynamic>? booking, // optional so you still have row data
  }) =>
      HydratedBookingResult._(
        false,
        null,
        null,
        booking,
        'Stored booking date is no longer available',
      );

  factory HydratedBookingResult.invalidTime({
    Map<String, dynamic>? booking,
  }) =>
      HydratedBookingResult._(
        false,
        null,
        null,
        booking,
        'Stored booking time is no longer available',
      );
}