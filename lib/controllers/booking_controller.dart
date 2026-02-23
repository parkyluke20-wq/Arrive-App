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

  int? selectedCustomer;
  int? selectedSite;

  /// Vehicle type object is owned by the UI layer.
  /// Controller treats it as an opaque value with known fields.
  dynamic selectedVehicleType;

  DateTime? selectedDate;
  DateTime? selectedStartTime;

  final Set<DateTime> bookableDates = {};
  final List<DateTime> availableStartTimes = [];

  bool computingDates = false;
  bool computingTimes = false;

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
    if (selectedCustomer == null ||
        selectedSite == null ||
        selectedVehicleType == null) {
      return;
    }

    computingDates = true;
    bookableDates.clear();
    notifyListeners();

    final pools = await availabilityService.allowedPools(
      customerId: selectedCustomer!,
      siteId: selectedSite!,
      loadType: selectedVehicleType.loadType,
    );

    if (pools.isEmpty) {
      computingDates = false;
      notifyListeners();
      return;
    }

    final nowUtc = DateTime.now().toUtc();
    final from = nowUtc.subtract(const Duration(days: 1));
    final to = from.add(const Duration(days: 60));
    final rows = await availabilityService.availabilityRows(
      siteId: selectedSite!,
      from: from,
      to: to,
    );

    final result = availabilityService.computeBookableDates(
      rows: rows,
      allowedPools: pools,
      requiredSlots: selectedVehicleType.slotUnitsRequired,
    );

    bookableDates
      ..clear()
      ..addAll(result);

    computingDates = false;
    notifyListeners();
  }

  Future<void> computeStartTimes() async {
    if (selectedCustomer == null ||
        selectedSite == null ||
        selectedVehicleType == null ||
        selectedDate == null) {
      return;
    }

    computingTimes = true;
    availableStartTimes.clear();
    notifyListeners();

    final pools = await availabilityService.allowedPools(
      customerId: selectedCustomer!,
      siteId: selectedSite!,
      loadType: selectedVehicleType.loadType,
    );

    if (pools.isEmpty) {
      computingTimes = false;
      notifyListeners();
      return;
    }

    final from = DateTime.utc(
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

    final result = availabilityService.computeStartTimes(
      rows: rows,
      allowedPools: pools,
      requiredSlots: selectedVehicleType.slotUnitsRequired,
    );

    availableStartTimes
      ..clear()
      ..addAll(result);

    computingTimes = false;
    notifyListeners();
  }

  // ---------------- EDIT HYDRATION ----------------

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
          DateTime.parse(row['start_time']).toUtc();

      selectedDate = DateTime(
        storedStart.year,
        storedStart.month,
        storedStart.day,
      );

      selectedStartTime = storedStart;

      notifyListeners();

      return HydratedBookingResult.success(
        restoredDate: selectedDate!,
        restoredStartTime: selectedStartTime!,
        booking: row,
      );
    } catch (e) {
      return HydratedBookingResult.invalidDate();
    }
  }

  // ---------------- HELPERS ----------------

  void _clearDateAndTime() {
    selectedDate = null;
    selectedStartTime = null;
    availableStartTimes.clear();
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