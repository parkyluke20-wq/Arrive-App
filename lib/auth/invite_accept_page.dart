import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../routing/app_routes.dart';
import '../theme/brand_colors.dart';
import '../theme/brand_text.dart';

class InviteAcceptPage extends StatefulWidget {
  const InviteAcceptPage({super.key});

  @override
  State<InviteAcceptPage> createState() => _InviteAcceptPageState();
}

class _InviteAcceptPageState extends State<InviteAcceptPage> {
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _loading = true;
  bool _submitting = false;
  String? _error;

  late final User _user;

  @override
  void initState() {
    super.initState();
    _initialise();
  }

  Future<void> _initialise() async {
    final session = Supabase.instance.client.auth.currentSession;

    if (session == null || session.user == null) {
      _fail('Invalid or expired invitation link');
      return;
    }

    _user = session.user;

    try {
      final existingUser = await Supabase.instance.client
          .from('users')
          .select()
          .eq('user_id', _user.id)
          .maybeSingle();

      if (existingUser == null) {
        await _provisionUser();
      }

      setState(() => _loading = false);
    } catch (_) {
      _fail('Unable to complete invitation');
    }
  }

  Future<void> _provisionUser() async {
    // NOTE:
    // customer_id + role MUST already be defined in invites table
    // This assumes you resolved invite → customer mapping server-side
    final invite = await Supabase.instance.client
        .from('invites')
        .select()
        .eq('email', _user.email!)
        .eq('accepted', false)
        .maybeSingle();

    if (invite == null) {
      throw Exception('Invite not found');
    }

    await Supabase.instance.client.from('users').insert({
      'user_id': _user.id,
      'email': _user.email,
      'name': _user.email!.split('@').first,
      'customer_id': invite['customer_id'],
      'role': invite['role'],
      'active': true,
    });

    await Supabase.instance.client
        .from('invites')
        .update({'accepted': true})
        .eq('invite_id', invite['invite_id']);
  }

  Future<void> _setPassword() async {
    final password = _passwordCtrl.text;
    final confirm = _confirmCtrl.text;

    if (password.length < 8) {
      _setError('Password must be at least 8 characters');
      return;
    }

    if (password != confirm) {
      _setError('Passwords do not match');
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

      if (!mounted) return;

      Navigator.pushReplacementNamed(
        context,
        AppRoutes.inboundOverview,
      );
    } on AuthException catch (e) {
      _setError(e.message);
    } catch (_) {
      _setError('Failed to set password');
    } finally {
      setState(() => _submitting = false);
    }
  }

  void _fail(String message) {
    setState(() {
      _error = message;
      _loading = false;
    });
  }

  void _setError(String message) {
    setState(() => _error = message);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Complete Your Account',
                  style: BrandText.title,
                ),

                const SizedBox(height: 16),

                Text(
                  'Welcome ${_user.email}',
                  style: BrandText.subtitle,
                ),

                const SizedBox(height: 32),

                TextField(
                  controller: _passwordCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'New Password',
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 16),

                TextField(
                  controller: _confirmCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirm Password',
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 24),

                if (_error != null)
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),

                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _setPassword,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: BrandColors.lightBlue,
                      foregroundColor: Colors.white,
                    ),
                    child: _submitting
                        ? const CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          )
                        : const Text('Activate Account'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
