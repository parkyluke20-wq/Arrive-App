import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/brand_colors.dart';

class AppScaffold extends StatelessWidget {
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

  Future<void> _logout(BuildContext context) async {
    await Supabase.instance.client.auth.signOut();

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
              title: const Text('Make a Booking'),
              onTap: () => _go(context, '/booking-form'),
            ),

            ListTile(
              title: const Text('Make a Reservation'),
              onTap: () => _go(context, '/reserve-slots'),
            ),

            ListTile(
              title: const Text('Inbound Overview'),
              onTap: () => _go(context, '/inbound-overview'),
            ),

            ListTile(
              title: const Text('All Bookings'),
              onTap: () => _go(context, '/all-bookings'),
            ),

            ListTile(
              title: const Text('Profile'),
              onTap: () => _go(context, '/profile'),
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
          title: Text(title),
          actions: [
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

      body: body,

      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (bottomActions != null)
            Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
              alignment: Alignment.centerRight,
              child: bottomActions,
            ),

          if (showFooter)
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