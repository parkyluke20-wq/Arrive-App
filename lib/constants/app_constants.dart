class AppConstants {
  AppConstants._();

  // Slot duration: each time slot is 30 minutes
  static const int slotDurationMinutes = 30;
  static const Duration slotDuration = Duration(minutes: slotDurationMinutes);

  // Minimum advance booking: bookings must be made at least 24 hours ahead
  static const int minAdvanceBookingHours = 24;
  static const Duration minAdvanceBooking = Duration(hours: minAdvanceBookingHours);

  // Booking window: availability is fetched up to 183 days (~6 months) ahead
  static const int bookingWindowDays = 183;

  // Upper bound for the slot availability query; 22 slots × 183 days × 3 pools = 12,078 — 15,000 adds headroom
  static const int maxSlotQueryLimit = 15000;

  // Maximum horizon for the date picker on the reserve-slots page
  static const int maxBookingHorizonDays = 183;

  // Session timeout
  static const Duration sessionTimeout = Duration(minutes: 240);

  // Rate-limit cooldown between password-reset emails
  static const Duration passwordResetCooldown = Duration(seconds: 30);

  // Brief UI pause after a successful reservation before navigating away
  static const Duration postReservationDelay = Duration(milliseconds: 500);
}
