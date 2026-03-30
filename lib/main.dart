import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'auth/auth_gate.dart';
import 'pages/reset_password_page.dart';
import 'services/session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:html' as html;

// APP PAGES
import 'pages/inbound_overview_page.dart';
import 'pages/booking_form_page.dart';
import 'pages/all_bookings_page.dart';
import 'pages/profile_page.dart';
import 'pages/reserve_slots_page.dart';

const String appVersion = '1.2';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  setUrlStrategy(HashUrlStrategy());

  await Supabase.initialize(
    url: 'https://eozwxanmzamutjztoxbo.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVvend4YW5temFtdXRqenRveGJvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk2MDg1ODAsImV4cCI6MjA4NTE4NDU4MH0.c_JcOuGel2K94PFUZW78y2t6wUiCV4JEOs0DMtxmc54',
  );

  runApp(const InboundBookingApp());
}

class InboundBookingApp extends StatefulWidget {
  const InboundBookingApp({super.key});

  @override
  State<InboundBookingApp> createState() => _InboundBookingAppState();
}

class _InboundBookingAppState extends State<InboundBookingApp> {
  final sessionManager = SessionManager();

  @override
  void initState() {
    super.initState();
    _checkAppVersion(); 
    _startSession();
  }

  void _startSession() {
    sessionManager.start(_handleTimeout);
  }

  void _resetSession() {
    sessionManager.reset(_handleTimeout);
  }

  void _handleTimeout() async {
    await Supabase.instance.client.auth.signOut();

    if (!mounted) return;

    Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
  }

  Future<void> _checkAppVersion() async {
  final prefs = await SharedPreferences.getInstance();
  final savedVersion = prefs.getString('app_version');

  if (savedVersion != appVersion) {
    await prefs.setString('app_version', appVersion);
    html.window.location.reload();
  }
}

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _resetSession,
      onPanDown: (_) => _resetSession(),

      child: MaterialApp(
        debugShowCheckedModeBanner: false,

        locale: const Locale('en', 'GB'),
        supportedLocales: const [
          Locale('en', 'GB'),
        ],

        localizationsDelegates: [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],

        initialRoute: '/',
        routes: {
          '/': (_) => const AuthGate(),
          '/reset-password': (_) => const ResetPasswordPage(),
          '/inbound-overview': (_) => const InboundOverviewPage(),
          '/booking-form': (_) => const BookingFormPage(),
          '/all-bookings': (_) => const AllBookingsPage(),
          '/profile': (_) => const ProfilePage(),
          '/reserve-slots': (_) => const ReserveSlotsPage(),
        },
      ),
    );
  }
}