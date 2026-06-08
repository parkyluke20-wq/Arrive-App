import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/notification_service.dart';
import '../services/notification_provider.dart';
import '../theme/brand_colors.dart';
import '../pages/booking_form_page.dart';

class NotificationPanel extends StatefulWidget {
  final VoidCallback onDismiss;

  const NotificationPanel({super.key, required this.onDismiss});

  @override
  State<NotificationPanel> createState() => _NotificationPanelState();
}

class _NotificationPanelState extends State<NotificationPanel> {
  @override
  void initState() {
    super.initState();
    NotificationProvider.instance.addListener(_onChanged);
  }

  @override
  void dispose() {
    NotificationProvider.instance.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _openBooking(AppNotification notification) {
    final bookingId = notification.bookingId;
    if (bookingId == null) return;

    NotificationService.instance.markRead(notification.id);
    final nav = Navigator.of(context);
    widget.onDismiss();
    nav.push(
      MaterialPageRoute(
        builder: (_) => const BookingFormPage(
          mode: BookingFormMode.view,
          returnRoute: '/inbound-overview',
        ),
        settings: RouteSettings(
          arguments: {
            'booking_id': bookingId,
            'mode': BookingFormMode.view,
          },
        ),
      ),
    );
  }

  Color _typeColor(NotificationType type) {
    switch (type) {
      case NotificationType.newBooking:
        return BrandColors.lightBlue;
      case NotificationType.bookingEdited:
        return BrandColors.deepBlue;
      case NotificationType.cancellation:
        return const Color(0xFFD9534F);
      case NotificationType.postBookingNote:
        return BrandColors.orange;
    }
  }

  IconData _typeIcon(NotificationType type) {
    switch (type) {
      case NotificationType.newBooking:
        return Icons.add_circle_outline;
      case NotificationType.bookingEdited:
        return Icons.edit_outlined;
      case NotificationType.cancellation:
        return Icons.cancel_outlined;
      case NotificationType.postBookingNote:
        return Icons.comment_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = NotificationProvider.instance;
    final notifications = provider.notifications;
    final unread = provider.unreadCount;
    final isLoading = provider.isLoading;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Notifications',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: BrandColors.charcoal,
                  ),
                ),
              ),
              if (unread > 0)
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => NotificationService.instance.markAllRead(),
                  child: const Text(
                    'Mark all read',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
        ),

        const Divider(height: 1),

        Expanded(
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : notifications.isEmpty
                  ? const Center(
                      child: Text(
                        'No notifications',
                        style: TextStyle(color: Colors.grey, fontSize: 14),
                      ),
                    )
                  : ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: notifications.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 14, endIndent: 14),
                      itemBuilder: (_, index) {
                        final n = notifications[index];
                        return _NotificationTile(
                          notification: n,
                          typeColor: _typeColor(n.type),
                          typeIcon: _typeIcon(n.type),
                          onTap: n.bookingId != null ? () => _openBooking(n) : null,
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Tile
// ─────────────────────────────────────────────

class _NotificationTile extends StatelessWidget {
  final AppNotification notification;
  final Color typeColor;
  final IconData typeIcon;
  final VoidCallback? onTap;

  const _NotificationTile({
    required this.notification,
    required this.typeColor,
    required this.typeIcon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: notification.isRead
            ? null
            : BrandColors.deepBlue.withValues(alpha: 0.04),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              margin: const EdgeInsets.only(right: 10, top: 1),
              decoration: BoxDecoration(
                color: typeColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(typeIcon, size: 16, color: typeColor),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        margin: const EdgeInsets.only(right: 6, bottom: 3),
                        decoration: BoxDecoration(
                          color: typeColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          notification.typeLabel,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: typeColor,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      if (!notification.isRead)
                        Container(
                          width: 5,
                          height: 5,
                          decoration: const BoxDecoration(
                            color: BrandColors.orange,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  Text(
                    notification.message,
                    style: TextStyle(
                      fontSize: 13,
                      color: BrandColors.charcoal,
                      fontWeight: notification.isRead
                          ? FontWeight.normal
                          : FontWeight.w500,
                    ),
                  ),
                  if (notification.customerName != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      notification.customerName!,
                      style: TextStyle(
                        fontSize: 11,
                        color: BrandColors.deepBlue,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  const SizedBox(height: 2),
                  Text(
                    _formatTime(notification.timestamp),
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) {
      final m = diff.inMinutes;
      return '$m minute${m == 1 ? '' : 's'} ago';
    }
    if (diff.inHours < 24) {
      final h = diff.inHours;
      return '$h hour${h == 1 ? '' : 's'} ago';
    }
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dtDay = DateTime(dt.year, dt.month, dt.day);
    if (dtDay == yesterday) {
      return 'Yesterday at ${DateFormat('HH:mm').format(dt)}';
    }
    return DateFormat('dd/MM/yyyy HH:mm').format(dt);
  }
}
