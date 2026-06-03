import 'dart:html' as html;

import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../services/user_session.dart';
import '../services/version_notifier.dart';
import '../services/notification_provider.dart';
import '../theme/brand_colors.dart';
import '../pages/booking_form_page.dart';
import '../routing/app_routes.dart';
import '../widgets/notification_panel.dart';

class AppScaffold extends StatefulWidget {
  final String title;
  final Widget body;
  final Widget? bottomActions;
  final bool showFooter;

  const AppScaffold({
    super.key,
    required this.title,
    required this.body,
    this.bottomActions,
    this.showFooter = true,
  });

  @override
  State<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends State<AppScaffold> {
  String? _effectiveRole;
  bool _isGlobalAdmin = false;
  bool _loadingRole = true;
  OverlayEntry? _notificationOverlay;

  @override
  void initState() {
    super.initState();
    _loadRole();
    NotificationProvider.instance.addListener(_onNotificationsChanged);
  }

  void _onNotificationsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadRole() async {
    if (supabase.auth.currentSession == null) {
      if (mounted) setState(() => _loadingRole = false);
      return;
    }

    try {
      _effectiveRole = await UserSession.instance.getRole();
      if (_effectiveRole == 'internal_admin') {
        _isGlobalAdmin = await UserSession.instance.isGlobalAdmin();
      }
    } catch (_) {
      // _effectiveRole stays null; role-gated nav items won't show
    } finally {
      if (mounted) setState(() => _loadingRole = false);
    }
  }

  @override
  void dispose() {
    _removeNotificationOverlay();
    NotificationProvider.instance.removeListener(_onNotificationsChanged);
    super.dispose();
  }

  Future<void> _logout(BuildContext context) async {
    UserSession.instance.clear();
    await supabase.auth.signOut();

    Navigator.of(context).pushNamedAndRemoveUntil(
      '/',
      (route) => false,
    );
  }

  void _go(BuildContext context, String route) {
    Navigator.of(context).pushNamedAndRemoveUntil(
      route,
      (route) => false,
    );
  }

  void _removeNotificationOverlay() {
    _notificationOverlay?.remove();
    _notificationOverlay = null;
  }

  void _toggleNotificationDropdown(BuildContext context) {
    if (_notificationOverlay != null) {
      _removeNotificationOverlay();
      setState(() {});
      return;
    }

    const dropdownWidth = 360.0;
    const appBarHeight = 90.0;
    final screenWidth = MediaQuery.of(context).size.width;
    final rightOffset = screenWidth < dropdownWidth + 16 ? 0.0 : 16.0;

    _notificationOverlay = OverlayEntry(
      builder: (ctx) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                _removeNotificationOverlay();
                setState(() {});
              },
            ),
          ),
          Positioned(
            top: appBarHeight + 6,
            right: rightOffset,
            width: dropdownWidth.clamp(0, screenWidth.toDouble()),
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(12),
              color: BrandColors.background,
              child: SizedBox(
                height: 440,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: NotificationPanel(
                    onDismiss: () {
                      _removeNotificationOverlay();
                      setState(() {});
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    Overlay.of(context).insert(_notificationOverlay!);
    setState(() {});
  }

  Widget _buildNotificationBell(BuildContext context) {
    final unread = NotificationProvider.instance.unreadCount;
    final isOpen = _notificationOverlay != null;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: Icon(
            isOpen ? Icons.notifications : Icons.notifications_none,
            color: Colors.white,
            size: 28,
          ),
          onPressed: () => _toggleNotificationDropdown(context),
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        if (unread > 0)
          Positioned(
            right: 6,
            top: 8,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                color: BrandColors.orange,
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              child: Text(
                unread > 99 ? '99+' : '$unread',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawerScrimColor: Colors.transparent,
      drawer: Drawer(
        backgroundColor: BrandColors.lightgrey,
        child: Column(
          children: [
            const DrawerHeader(
              child: Text(
                'Navigation',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            ListTile(
              leading: const Icon(Icons.home_outlined),
              title: const Text('Home'),
              onTap: () => _go(context, AppRoutes.inboundOverview),
            ),

            ListTile(
              title: const Text('Make a Booking'),
              onTap: () {
                Navigator.of(context).pop();

                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BookingFormPage(
                      mode: BookingFormMode.create,
                      returnRoute: '/inbound-overview',
                    ),
                  ),
                );
              },
            ),

            if (_effectiveRole == 'internal_admin' ||
                _effectiveRole == 'internal_user')
              ListTile(
                title: const Text('Make a Reservation'),
                onTap: () => _go(context, AppRoutes.reserveSlots),
              ),

            if (_effectiveRole == 'internal_admin' ||
                _effectiveRole == 'internal_user')
              ListTile(
                title: const Text('All Reservations'),
                onTap: () => _go(context, AppRoutes.allReservations),
              ),

            if (_effectiveRole == 'internal_admin' ||
                _effectiveRole == 'internal_user')
              ListTile(
                title: const Text('Manual Booking'),
                onTap: () => _go(context, AppRoutes.manualBooking),
              ),

            ListTile(
              title: const Text('All Bookings'),
              onTap: () => _go(context, AppRoutes.allBookings),
            ),

            ListTile(
              title: const Text('Profile'),
              onTap: () => _go(context, AppRoutes.profile),
            ),

            if (_isGlobalAdmin)
              ListTile(
                title: const Text('Settings'),
                onTap: () => _go(context, AppRoutes.settings),
              ),

            const Spacer(),
            const Divider(),

            ListTile(
              leading: const Icon(Icons.logout, size: 32),
              title: const Text(
                'Logout',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () => _logout(context),
            ),
          ],
        ),
      ),

      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(90),
        child: AppBar(
          backgroundColor: BrandColors.deepBlue,
          toolbarHeight: 72,
          centerTitle: false,
          iconTheme: const IconThemeData(color: Colors.white),
          titleTextStyle: const TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.w600,
          ),
          title: Text(widget.title),
          actions: [
            _buildNotificationBell(context),
            const SizedBox(width: 24),
            Padding(
              padding: const EdgeInsets.only(right: 24, top: 10),
              child: Center(
                child: Image.asset(
                  'assets/images/expect_logo.png',
                  height: 70,
                ),
              ),
            ),
          ],
        ),
      ),

      body: Column(
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: newVersionAvailable,
            builder: (context, hasNewVersion, _) {
              if (!hasNewVersion) return const SizedBox.shrink();
              return Container(
                width: double.infinity,
                color: Colors.amber,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'A new version is available',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    TextButton(
                      onPressed: () => html.window.location.reload(),
                      child: const Text('Update now'),
                    ),
                  ],
                ),
              );
            },
          ),
          Expanded(child: widget.body),
        ],
      ),

      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.bottomActions != null)
            Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
              alignment: Alignment.centerRight,
              child: widget.bottomActions,
            ),

          if (widget.showFooter)
            const SizedBox(
              height: 60,
              child: Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Center(
                  child: Text(
                    'Deliveries must be booked at least 24 hours before arrival',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}