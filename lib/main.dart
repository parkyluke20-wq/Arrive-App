import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'auth/auth_gate.dart';
import 'auth/invite_accept_page.dart';
import 'pages/reset_password_page.dart';
import 'routing/app_routes.dart';
import 'services/session_manager.dart';
import 'services/supabase_service.dart';
import 'services/user_session.dart';
import 'services/version_check_service.dart';
import 'services/version_notifier.dart';
import 'services/notification_service.dart';
import 'services/notification_provider.dart';
import 'theme/brand_colors.dart';

// APP PAGES
import 'pages/inbound_overview_page.dart';
import 'pages/booking_form_page.dart';
import 'pages/all_bookings_page.dart';
import 'pages/profile_page.dart';
import 'pages/reserve_slots_page.dart';
import 'pages/all_reservations_page.dart';
import 'pages/settings_page.dart';
import 'pages/manual_booking_page.dart';

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

class _InboundBookingAppState extends State<InboundBookingApp>
    with WidgetsBindingObserver {
  final sessionManager = SessionManager();
  late final VersionCheckService _versionCheckService;
  late final StreamSubscription<AuthState> _authSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startSession();
    _versionCheckService = VersionCheckService(
      onNewVersionAvailable: () => newVersionAvailable.value = true,
    );
    _versionCheckService.init();

    _authSubscription = supabase.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedIn) {
        NotificationService.instance.start();
      } else if (data.event == AuthChangeEvent.signedOut) {
        NotificationService.instance.stop();
        NotificationProvider.instance.clear();
      }
    });

    if (supabase.auth.currentSession != null) {
      NotificationService.instance.start();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription.cancel();
    NotificationService.instance.stop();
    _versionCheckService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      NotificationService.instance.stop();
    } else if (state == AppLifecycleState.resumed) {
      if (supabase.auth.currentSession != null) {
        NotificationService.instance.start();
      }
    }
  }

  void _startSession() {
    sessionManager.start(_handleTimeout);
  }

  void _resetSession() {
    sessionManager.reset(_handleTimeout);
  }

  void _handleTimeout() async {
    UserSession.instance.clear();
    await supabase.auth.signOut();

    if (!mounted) return;

    Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.root, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _resetSession(),
      onPointerMove: (_) => _resetSession(),
      onPointerSignal: (_) => _resetSession(),

      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          scaffoldBackgroundColor: BrandColors.background,
          canvasColor: BrandColors.background,
          colorScheme: ColorScheme.light(
            primary: BrandColors.charcoal,
            onPrimary: Colors.white,
            secondary: BrandColors.charcoal,
            onSecondary: Colors.white,
            surface: BrandColors.background,
            outline: Colors.grey.shade400,
          ),
          dividerColor: Colors.grey.shade400,
          inputDecorationTheme: InputDecorationTheme(
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.grey.shade600),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.grey.shade400),
            ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              foregroundColor: BrandColors.charcoal,
              side: BorderSide(color: Colors.grey.shade400),
            ),
          ),
        ),

        locale: const Locale('en', 'GB'),
        supportedLocales: const [
          Locale('en', 'GB'),
        ],

        localizationsDelegates: [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],

        initialRoute: AppRoutes.root,
        routes: {
          AppRoutes.root: (_) => const AuthGate(),
          AppRoutes.resetPassword: (_) => const ResetPasswordPage(),
          AppRoutes.inboundOverview: (_) => const InboundOverviewPage(),
          AppRoutes.bookingForm: (_) => const BookingFormPage(),
          AppRoutes.allBookings: (_) => const AllBookingsPage(),
          AppRoutes.profile: (_) => const ProfilePage(),
          AppRoutes.reserveSlots: (_) => const ReserveSlotsPage(),
          AppRoutes.allReservations: (_) => const AllReservationsPage(),
          AppRoutes.settings: (_) => const SettingsPage(),
          AppRoutes.manualBooking: (_) => const ManualBookingPage(),
          AppRoutes.inviteAccept: (_) => const InviteAcceptPage(),
        },
      ),
    );
  }
}