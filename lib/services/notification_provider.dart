import 'package:flutter/foundation.dart';
import 'notification_service.dart';

class NotificationProvider extends ChangeNotifier {
  static final instance = NotificationProvider._();
  NotificationProvider._();

  final List<AppNotification> _notifications = [];

  List<AppNotification> get notifications => List.unmodifiable(_notifications);

  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  void add(AppNotification notification) {
    _notifications.insert(0, notification);
    notifyListeners();
  }

  void markRead(String id) {
    final idx = _notifications.indexWhere((n) => n.id == id);
    if (idx == -1) return;
    _notifications[idx] = _notifications[idx].copyWith(isRead: true);
    notifyListeners();
  }

  void markAllRead() {
    var changed = false;
    for (var i = 0; i < _notifications.length; i++) {
      if (!_notifications[i].isRead) {
        _notifications[i] = _notifications[i].copyWith(isRead: true);
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  void clear() {
    if (_notifications.isEmpty) return;
    _notifications.clear();
    notifyListeners();
  }
}
