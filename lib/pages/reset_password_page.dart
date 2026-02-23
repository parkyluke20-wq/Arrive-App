import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/brand_text.dart';
import '../theme/brand_colors.dart';

class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  bool _loading = true;
  bool _submitting = false;
  String? _error;

  @override
    void initState() {
      super.initState();

      Supabase.instance.client.auth.onAuthStateChange.listen((data) {
        if (data.event == AuthChangeEvent.passwordRecovery) {
          setState(() => _loading = false);
        }
      });

      _initRecovery();
    }


  Future<void> _initRecovery() async {
    final uri = Uri.base;
    final code = uri.queryParameters['code'];

    if (code == null) {
      setState(() {
        _error = 'Invalid or expired password reset link.';
        _loading = false;
      });
      return;
    }

    try {
      await Supabase.instance.client.auth.exchangeCodeForSession(code);
      setState(() => _loading = false);
    } catch (_) {
      setState(() {
        _error = 'Invalid or expired password reset link.';
        _loading = false;
      });
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
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: password),
      );

      await Supabase.instance.client.auth.signOut();

      if (mounted) {
        Navigator.pushReplacementNamed(context, '/');
      }
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Unexpected error occurred.');
    } finally {
      setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Set your password', style: BrandText.title),
              const SizedBox(height: 24),

              if (_loading)
                const Text('Loading recovery session…')
              else if (_error != null)
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                )
              else ...[
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'New password',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _confirmController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirm password',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),

                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: BrandColors.lightBlue,
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(
                      inherit: false,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text('Set password'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
