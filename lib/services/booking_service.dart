import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';

import '../constants/app_constants.dart';
import '../controllers/booking_controller.dart';

class BookingService {
  final SupabaseClient supabase;

  BookingService(this.supabase);

  // ---------------- CONSTANTS ----------------

  static const String STATUS_DRAFT = 'draft';
  static const String STATUS_BOOKED = 'booked';

  // ---------------- PAYLOAD ----------------

  Map<String, dynamic> _bookingPayload({
    required BookingController controller,
    required int vehicleTypeId,
    required int slotUnitsRequired,
    required String status,
    required DateTime start,
    required DateTime end,
    required String reference,
    required String carrier,
    String? vehicleReg,
    String? container,
    int? qtyPallets,
    int? qtyCases,
  }) {
    return {
      'customer_id': controller.selectedCustomer,
      'site_id': controller.selectedSite,
      'vehicle_type_id': vehicleTypeId,

      // ---- timing ----
      'start_time': start.toIso8601String(),
      'end_time': end.toIso8601String(),
      'booking_date': DateTime(
        start.year,
        start.month,
        start.day,
      ).toIso8601String(),

      // ---- capacity ----
      'lane_units_used': slotUnitsRequired,

      // ---- delivery details ----
      'reference': reference.trim(),
      'carrier': carrier.trim(),
      'vehicle_reg': vehicleReg?.isNotEmpty == true ? vehicleReg : null,
      'container_number': container?.isNotEmpty == true ? container : null,
      'qty_pallets': qtyPallets,
      'qty_cases': qtyCases,

      // ---- status ----
      'status': status,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  // ---------------- SAVE DRAFT ----------------

  Future<void> saveDraft({
    required BookingController controller,
    required int vehicleTypeId,
    required int slotUnitsRequired,
    String? bookingId,
    required String reference,
    required String carrier,
    String? vehicleReg,
    String? container,
    int? qtyPallets,
    int? qtyCases,
  }) async {
    if (controller.selectedStartTime == null) return;

    final start = controller.selectedStartTime!;
    final end = start.add(Duration(minutes: slotUnitsRequired * AppConstants.slotDurationMinutes));

    final basePayload = _bookingPayload(
      controller: controller,
      vehicleTypeId: vehicleTypeId,
      slotUnitsRequired: slotUnitsRequired,
      status: STATUS_DRAFT,
      start: start,
      end: end,
      reference: reference,
      carrier: carrier,
      vehicleReg: vehicleReg,
      container: container,
      qtyPallets: qtyPallets,
      qtyCases: qtyCases,
    );

    if (bookingId != null) {
      await supabase
          .from('bookings')
          .update(basePayload)
          .eq('booking_id', bookingId);
    } else {
      final user = supabase.auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      final insertPayload = Map<String, dynamic>.from(basePayload);
      insertPayload['created_by'] = user.id;

      await supabase.from('bookings').insert(insertPayload);
    }
  }

  // ---------------- CONFIRM BOOKING ----------------

  Future<Map<String, dynamic>> confirmBooking({
    required BookingController controller,
    required int vehicleTypeId,
    required int slotUnitsRequired,
    String? bookingId,
    required String reference,
    required String carrier,
    String? vehicleReg,
    String? container,
    int? qtyPallets,
    int? qtyCases,
    PlatformFile? packingListFile,
    String? existingPackingListPath,
    required bool packingListRemoved,
  }) async {
    if (controller.selectedStartTime == null) {
      throw Exception('Start time is required');
    }

    final start = controller.selectedStartTime!;
    final end = start.add(Duration(minutes: slotUnitsRequired * AppConstants.slotDurationMinutes));

    // ----------------------------------------------------
    // 🔒 24 HOUR BUSINESS RULE ENFORCEMENT
    // ----------------------------------------------------
    final now = DateTime.now();
    final minimumAllowed = now.add(AppConstants.minAdvanceBooking);

    if (start.isBefore(minimumAllowed)) {
      throw Exception(
        'Bookings must be made at least 24 hours before arrival.',
      );
    }
    // ----------------------------------------------------

    String? resolvedBookingId;

    final payload = _bookingPayload(
      controller: controller,
      vehicleTypeId: vehicleTypeId,
      slotUnitsRequired: slotUnitsRequired,
      status: STATUS_BOOKED,
      start: start,
      end: end,
      reference: reference,
      carrier: carrier,
      vehicleReg: vehicleReg,
      container: container,
      qtyPallets: qtyPallets,
      qtyCases: qtyCases,
    );

    try {
      Map<String, dynamic>? bookingRow;
      // ---------- INSERT OR UPDATE BOOKING ----------
      if (bookingId != null) {

        final update = await supabase
            .from('bookings')
            .update(payload)
            .eq('booking_id', bookingId)
            .select('booking_id, booking_ref')
            .single();

        resolvedBookingId = update['booking_id'].toString();
        bookingRow = update;

      } else {

        final user = supabase.auth.currentUser;
        if (user == null) {
          throw Exception('User not authenticated');
        }

        final insertPayload = Map<String, dynamic>.from(payload);
        insertPayload['created_by'] = user.id;

        final insert = await supabase
            .from('bookings')
            .insert(insertPayload)
            .select('booking_id, booking_ref')
            .single();

        resolvedBookingId = insert['booking_id'].toString();
        bookingRow = insert;
      }

      // ---------- PACKING LIST LOGIC ----------
      if (packingListFile != null) {

        final extension =
            packingListFile.name.split('.').last;

        final storagePath =
            'booking_$resolvedBookingId.$extension';

        await supabase.storage
            .from('booking-documents')
            .uploadBinary(
              storagePath,
              packingListFile.bytes!,
              fileOptions: const FileOptions(
                upsert: true,
              ),
            );

        await supabase
            .from('bookings')
            .update({
              'packing_list_path': storagePath,
            })
            .eq('booking_id', resolvedBookingId);

      } 
      else if (packingListRemoved &&
          existingPackingListPath != null) {

        await supabase.storage
            .from('booking-documents')
            .remove([existingPackingListPath]);

        await supabase
            .from('bookings')
            .update({
              'packing_list_path': null,
            })
            .eq('booking_id', resolvedBookingId)
            .select();
      }
    if (bookingRow == null) {
      throw Exception('Booking row not returned');
    }
    return bookingRow;
    } catch (e) {

      if (bookingId == null && resolvedBookingId != null) {
        await supabase
            .from('bookings')
            .delete()
            .eq('booking_id', resolvedBookingId)
            .select();
      }

      rethrow;
    }
  }
}

