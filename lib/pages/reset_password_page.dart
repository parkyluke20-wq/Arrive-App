import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/brand_text.dart';
import '../services/supabase_service.dart';
import '../services/user_session.dart';
import '../theme/brand_colors.dart';

class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  static const double _leftPadding = 350;
  static const double _verticalSpacing = 24;

  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  bool _loading = true;
  bool _submitting = false;
  bool _success = false;
  String? _fatalError;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initRecovery();
  }

  Future<void> _initRecovery() async {
    // With HashUrlStrategy the route lives inside the URL fragment:
    //   /#/reset-password?code=abc123
    // Uri.base.queryParameters is empty in that case; parse from the fragment instead.
    final fragment = Uri.base.fragment;
    final fragmentQuery = fragment.contains('?') ? fragment.split('?').last : '';
    final code = Uri.splitQueryString(fragmentQuery)['code']
        ?? Uri.base.queryParameters['code'];

    if (code == null) {
      if (mounted) {
        setState(() {
          _fatalError = 'Invalid or expired password reset link.';
          _loading = false;
        });
      }
      return;
    }

    // Exchange the one-time code for an active session (PKCE flow).
    // Without this, updateUser() has no session and throws "Auth session missing".
    try {
      await supabase.auth.exchangeCodeForSession(code);
      if (mounted) setState(() => _loading = false);
    } on AuthException catch (e) {
      if (mounted) setState(() { _fatalError = e.message; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _fatalError = 'Invalid or expired password reset link.'; _loading = false; });
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;

    final password = _passwordController.text;
    final confirm = _confirmController.text;

    if (password.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters.');
      return;
    }

    if (password != confirm) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }

    setState(() {
      _error = null;
      _submitting = true;
    });

    try {
      await supabase.auth.updateUser(
        UserAttributes(password: password),
      );

      if (!mounted) return;

      // Clear the recovery code from the URL before signing out so that
      // AuthGate's Uri.base check no longer sees `code` on its next rebuild,
      // and renders SignInPage instead of ResetPasswordPage.
      html.window.history.replaceState(null, '', '/');
      setState(() => _success = true);

      await Future.delayed(const Duration(seconds: 2));

      UserSession.instance.clear();
      await supabase.auth.signOut();
      // AuthGate rebuilds → no code in URL, no session → shows SignInPage.

    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Unexpected error occurred.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              color: Colors.white,
              child: Center(
                child: Image.asset(
                  'assets/images/login_background.png',
                  fit: BoxFit.cover,
                  alignment: Alignment.centerRight,
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(_leftPadding, 0, 40, 0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 40),
                          child: Text('Set your password', style: BrandText.title),
                        ),

                        const SizedBox(height: 40),

                        if (_loading)
                          const Text('Loading recovery session…')
                        else if (_fatalError != null)
                          Text(
                            _fatalError!,
                            style: const TextStyle(color: Colors.red),
                          )
                        else if (_success)
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Password reset successfully.',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Redirecting you to login…',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ],
                          )
                        else ...[
                          if (_error != null) ...[
                            Text(
                              _error!,
                              style: const TextStyle(color: Colors.red),
                            ),
                            const SizedBox(height: _verticalSpacing),
                          ],

                          AutofillGroup(
                            child: Column(
                              children: [
                                SizedBox(
                                  width: double.infinity,
                                  child: TextField(
                                    controller: _passwordController,
                                    obscureText: true,
                                    autofillHints: const [AutofillHints.newPassword],
                                    onChanged: (_) {
                                      if (_error != null) setState(() => _error = null);
                                    },
                                    decoration: const InputDecoration(
                                      labelText: 'New password',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: _verticalSpacing),
                                SizedBox(
                                  width: double.infinity,
                                  child: TextField(
                                    controller: _confirmController,
                                    obscureText: true,
                                    autofillHints: const [AutofillHints.newPassword],
                                    onChanged: (_) {
                                      if (_error != null) setState(() => _error = null);
                                    },
                                    onSubmitted: (_) => _submit(),
                                    decoration: const InputDecoration(
                                      labelText: 'Confirm password',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: _verticalSpacing),

                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: BrandColors.lightBlue,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: _submitting ? null : _submit,
                              child: _submitting
                                  ? const CircularProgressIndicator()
                                  : const Text('Set password'),
                            ),
                          ),
                        ],
                      ],
                    ),
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
