import 'package:flutter/foundation.dart';
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
  final String? customerName;
  final DateTime timestamp;
  final bool isRead;

  const AppNotification({
    required this.id,
    required this.type,
    required this.message,
    this.bookingId,
    this.customerName,
    required this.timestamp,
    this.isRead = false,
  });

  factory AppNotification.fromDb(Map<String, dynamic> row, {String? customerName}) {
    final typeStr = row['type'] as String? ?? '';
    final type = switch (typeStr) {
      'new_booking' => NotificationType.newBooking,
      'edit' => NotificationType.bookingEdited,
      'cancellation' => NotificationType.cancellation,
      'note' => NotificationType.postBookingNote,
      _ => NotificationType.newBooking,
    };
    return AppNotification(
      id: row['notification_id'] as String,
      type: type,
      message: row['title'] as String,
      bookingId: row['reference_id'] as String?,
      customerName: customerName,
      timestamp: DateTime.parse(row['created_at'] as String).toLocal(),
      isRead: row['read'] as bool? ?? false,
    );
  }

  AppNotification copyWith({bool? isRead, String? customerName}) => AppNotification(
        id: id,
        type: type,
        message: message,
        bookingId: bookingId,
        customerName: customerName ?? this.customerName,
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
  bool _starting = false;

  Future<void> start() async {
    if (_channel != null || _starting) return;
    _starting = true;
    try {
      await _loadNotifications();
      _subscribeRealtime();
    } finally {
      _starting = false;
    }
  }

  void stop() {
    if (_channel == null) return;
    final ch = _channel!;
    _channel = null;
    supabase.removeChannel(ch);
  }

  Future<void> _loadNotifications() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    NotificationProvider.instance.setLoading(true);
    try {
      final rows = await supabase
          .from('notifications')
          .select()
          .eq('user_id', userId)
          .order('read', ascending: true)
          .order('created_at', ascending: false);

      final customerNames = await _fetchCustomerNames(
        rows
            .map((r) => r['reference_id'] as String?)
            .whereType<String>()
            .toSet()
            .toList(),
      );

      final notifications = rows
          .map((row) => AppNotification.fromDb(
                row,
                customerName: customerNames[row['reference_id'] as String?],
              ))
          .toList();

      NotificationProvider.instance.setAll(notifications);
    } catch (e) {
      debugPrint('Notification load error: $e');
    } finally {
      NotificationProvider.instance.setLoading(false);
    }
  }

  Future<Map<String, String>> _fetchCustomerNames(List<String> bookingIds) async {
    if (bookingIds.isEmpty) return {};
    try {
      final rows = await supabase
          .from('bookings')
          .select('booking_id, customers(customer_name)')
          .inFilter('booking_id', bookingIds);
      return {
        for (final r in rows as List)
          if (r['booking_id'] != null &&
              r['customers']?['customer_name'] != null)
            r['booking_id'] as String: r['customers']['customer_name'] as String,
      };
    } catch (_) {
      return {};
    }
  }

  void _subscribeRealtime() {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    _channel = supabase
        .channel('user_notifications')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: _onNotificationInsert,
        )
        .subscribe();
  }

  void _onNotificationInsert(PostgresChangePayload payload) async {
    final bookingId = payload.newRecord['reference_id'] as String?;
    final customerNames = await _fetchCustomerNames(
      bookingId != null ? [bookingId] : [],
    );
    final notification = AppNotification.fromDb(
      payload.newRecord,
      customerName: bookingId != null ? customerNames[bookingId] : null,
    );
    NotificationProvider.instance.prepend(notification);
  }

  Future<void> markRead(String notificationId) async {
    NotificationProvider.instance.markRead(notificationId);
    try {
      await supabase
          .from('notifications')
          .update({'read': true})
          .eq('notification_id', notificationId);
    } catch (_) {
      // Optimistic update already applied
    }
  }

  Future<void> markAllRead() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    NotificationProvider.instance.markAllRead();
    try {
      await supabase
          .from('notifications')
          .update({'read': true})
          .eq('user_id', userId)
          .eq('read', false);
    } catch (_) {
      // Optimistic update already applied
    }
  }
}
