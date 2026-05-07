import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../pages/sign_in_page.dart';
import '../services/supabase_service.dart';
import '../pages/inbound_overview_page.dart';
import '../pages/reset_password_page.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: supabase.auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final uri = Uri.base;
        final hasRecoveryCode = uri.queryParameters.containsKey('code');

        if (hasRecoveryCode) {
          return const ResetPasswordPage();
        }

        final session = supabase.auth.currentSession;
        final forceReset =
            session?.user.userMetadata?['force_password_reset'] == true;

        if (session == null || forceReset) {
          return const SignInPage();
        }

        return const InboundOverviewPage();
      },
    );
  }
}
