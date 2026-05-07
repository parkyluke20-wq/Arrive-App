class AppConstants {
  AppConstants._();

  // Slot duration: each time slot is 30 minutes
  static const int slotDurationMinutes = 30;
  static const Duration slotDuration = Duration(minutes: slotDurationMinutes);

  // Minimum advance booking: bookings must be made at least 24 hours ahead
  static const int minAdvanceBookingHours = 24;
  static const Duration minAdvanceBooking = Duration(hours: minAdvanceBookingHours);

  // Booking window: availability is fetched up to 60 days ahead
  static const int bookingWindowDays = 60;

  // Upper bound for the slot availability query; 22 slots × 60 days × 3 pools = 3,960 — 5,000 adds headroom
  static const int maxSlotQueryLimit = 5000;

  // Maximum horizon for the date picker on the reserve-slots page
  static const int maxBookingHorizonDays = 90;

  // Session timeout
  static const Duration sessionTimeout = Duration(minutes: 240);

  // Rate-limit cooldown between password-reset emails
  static const Duration passwordResetCooldown = Duration(seconds: 30);

  // Brief UI pause after a successful reservation before navigating away
  static const Duration postReservationDelay = Duration(milliseconds: 500);
}
