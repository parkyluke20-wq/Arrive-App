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
        // Support both PKCE (`code`) and token-hash (`token_hash`) flows.
        // token_hash is the preferred flow: it requires no localStorage and
        // works when the user opens the email link in a different browser.
        final fragment = uri.fragment;
        final fragmentQuery =
            fragment.contains('?') ? fragment.split('?').last : '';
        final fragmentParams = Uri.splitQueryString(fragmentQuery);
        final hasRecovery = uri.queryParameters.containsKey('code') ||
            uri.queryParameters.containsKey('token_hash') ||
            fragmentParams.containsKey('code') ||
            fragmentParams.containsKey('token_hash');

        if (hasRecovery) {
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
