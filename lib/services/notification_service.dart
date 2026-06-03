import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';
import 'notification_provider.dart';

// ─────────────────────────────────────────────
// Model
// ─────────────────────────────────────────────

enum NotificationType { newBooking, bookingEdited, cancellation, postBookingNote }

class AppNotification {
  final String id;
  final NotificationType type;
  final String message;
  final String? bookingId;
  final String? bookingRef;
  final DateTime timestamp;
  final bool isRead;

  const AppNotification({
    required this.id,
    required this.type,
    required this.message,
    this.bookingId,
    this.bookingRef,
    required this.timestamp,
    this.isRead = false,
  });

  AppNotification copyWith({bool? isRead}) => AppNotification(
        id: id,
        type: type,
        message: message,
        bookingId: bookingId,
        bookingRef: bookingRef,
        timestamp: timestamp,
        isRead: isRead ?? this.isRead,
      );

  String get typeLabel {
    switch (type) {
      case NotificationType.newBooking:
        return 'New Booking';
      case NotificationType.bookingEdited:
        return 'Booking Updated';
      case NotificationType.cancellation:
        return 'Cancellation';
      case NotificationType.postBookingNote:
        return 'New Note';
    }
  }
}

// ─────────────────────────────────────────────
// Service
// ─────────────────────────────────────────────

class NotificationService {
  static final instance = NotificationService._();
  NotificationService._();

  RealtimeChannel? _channel;
  int _idCounter = 0;

  void start() {
    if (_channel != null) return;

    _channel = supabase
        .channel('app_notifications')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'bookings',
          callback: _onBookingInsert,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'bookings',
          callback: _onBookingUpdate,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'booking_events',
          callback: _onBookingEventInsert,
        )
        .subscribe();
  }

  void stop() {
    if (_channel == null) return;
    final ch = _channel!;
    _channel = null;
    supabase.removeChannel(ch);
  }

  String _newId() => '${DateTime.now().millisecondsSinceEpoch}_${_idCounter++}';

  void _onBookingInsert(PostgresChangePayload payload) {
    final record = payload.newRecord;
    final status = record['status'] as String?;
    if (status == 'draft') return;

    final ref = record['booking_ref']?.toString() ??
        record['booking_id']?.toString() ??
        '—';

    NotificationProvider.instance.add(AppNotification(
      id: _newId(),
      type: NotificationType.newBooking,
      message: 'New booking submitted: $ref',
      bookingId: record['booking_id']?.toString(),
      bookingRef: record['booking_ref']?.toString(),
      timestamp: DateTime.now(),
    ));
  }

  void _onBookingUpdate(PostgresChangePayload payload) {
    final record = payload.newRecord;
    final status = record['status'] as String?;
    if (status == 'draft') return;

    final ref = record['booking_ref']?.toString() ??
        record['booking_id']?.toString() ??
        '—';

    if (status == 'cancelled') {
      NotificationProvider.instance.add(AppNotification(
        id: _newId(),
        type: NotificationType.cancellation,
        message: 'Booking cancelled: $ref',
        bookingId: record['booking_id']?.toString(),
        bookingRef: record['booking_ref']?.toString(),
        timestamp: DateTime.now(),
      ));
    } else {
      NotificationProvider.instance.add(AppNotification(
        id: _newId(),
        type: NotificationType.bookingEdited,
        message: 'Booking updated: $ref',
        bookingId: record['booking_id']?.toString(),
        bookingRef: record['booking_ref']?.toString(),
        timestamp: DateTime.now(),
      ));
    }
  }

  void _onBookingEventInsert(PostgresChangePayload payload) {
    final record = payload.newRecord;
    // Only surface notes explicitly flagged as post-booking.
    final isPostBooking = record['added_post_booking'] as bool? ?? false;
    if (!isPostBooking) return;

    final bookingId = record['booking_id']?.toString();

    NotificationProvider.instance.add(AppNotification(
      id: _newId(),
      type: NotificationType.postBookingNote,
      message: 'A note was added to a booking',
      bookingId: bookingId,
      timestamp: DateTime.now(),
    ));
  }
}
