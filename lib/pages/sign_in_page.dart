import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/brand_text.dart';
import '../theme/brand_colors.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  // ---- Layout tuning ----
  static const double leftPadding = 350;
  static const double verticalSpacing = 24;
  // -----------------------

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  String? _errorMessage;
  String? _infoMessage;
  bool _isLoading = false;
  bool _forcePasswordReset = false;

  DateTime? _lastResetSentAt;
  static const Duration _resetCooldown = Duration(seconds: 30);

  bool get _canSendReset =>
      _lastResetSentAt == null ||
      DateTime.now().difference(_lastResetSentAt!) > _resetCooldown;

  @override
  void initState() {
    super.initState();
    _loadRememberedEmail();
  }

  // ---------------------------------------------------------------------------
  // SAFE STATE HELPERS
  // ---------------------------------------------------------------------------

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  void _setError(String message) {
    _safeSetState(() {
      _errorMessage = message;
      _infoMessage = null;
      _isLoading = false;
    });
  }

  void _setInfo(String message) {
    _safeSetState(() {
      _infoMessage = message;
      _errorMessage = null;
      _isLoading = false;
    });
  }

  // ---------------------------------------------------------------------------
  // INIT
  // ---------------------------------------------------------------------------

  Future<void> _loadRememberedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    final savedEmail = prefs.getString('remembered_email');
    if (savedEmail != null) {
      _emailController.text = savedEmail;
    }
  }

  // ---------------------------------------------------------------------------
  // LOGIN
  // ---------------------------------------------------------------------------

  Future<void> _handleLogin() async {
    if (_isLoading) return;

    _safeSetState(() {
      _errorMessage = null;
      _infoMessage = null;
      _isLoading = true;
    });

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty) return _setError('Email address is required');
    if (password.isEmpty) return _setError('Password is required');

    try {
      final res =
          await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (!mounted) return;

      final user = res.user;
      if (user == null) return _setError('Invalid email or password');

      final forceReset =
          user.userMetadata?['force_password_reset'] == true;

      if (forceReset) {
        _safeSetState(() {
          _forcePasswordReset = true;
          _isLoading = false;
        });
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('remembered_email', email);
      // AuthGate handles navigation

    } on AuthException {
      _setError('Invalid email or password');
    } catch (_) {
      _setError('Unexpected error occurred');
    }
  }

  // ---------------------------------------------------------------------------
  // PASSWORD RESET (FORCED FIRST LOGIN)
  // ---------------------------------------------------------------------------

  Future<void> _handlePasswordReset() async {
    if (_isLoading) return;

    final newPassword = _newPasswordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (newPassword.isEmpty || confirmPassword.isEmpty) {
      return _setError('Both password fields are required');
    }

    if (newPassword.length < 6) {
      return _setError('Password must be at least 6 characters long');
    }

    if (newPassword != confirmPassword) {
      return _setError('Passwords do not match');
    }

    _safeSetState(() {
      _errorMessage = null;
      _isLoading = true;
    });

    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(
          password: newPassword,
          data: {'force_password_reset': false},
        ),
      );

      if (!mounted) return;

      _safeSetState(() {
        _forcePasswordReset = false;
        _isLoading = false;
      });
      // AuthGate now allows navigation

    } on AuthException catch (e) {
      _setError(e.message);
    } catch (_) {
      _setError('Failed to update password');
    }
  }

  // ---------------------------------------------------------------------------
  // FORGOT PASSWORD
  // ---------------------------------------------------------------------------

  Future<void> _sendPasswordReset() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return _setError('Enter your email address');

    if (!_canSendReset) {
      return _setInfo(
        'Please wait before requesting another reset.',
      );
    }

    _safeSetState(() {
      _errorMessage = null;
      _isLoading = true;
    });

    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);

      if (!mounted) return;

      _safeSetState(() {
        _lastResetSentAt = DateTime.now();
        _infoMessage = 'Password reset email sent';
        _isLoading = false;
      });
    } catch (_) {
      _setError('Failed to send reset email');
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

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
              padding: const EdgeInsets.fromLTRB(350, 0, 40, 0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 40),
                          child: Text(
                            'Expect Distribution\nInbound Booking Diary',
                            style: BrandText.title,
                          ),
                        ),

                        const SizedBox(height: 40),

                        Text(
                          _forcePasswordReset ? 'Reset Password:' : 'Login:',
                          style: BrandText.subtitle,
                        ),

                        const SizedBox(height: verticalSpacing),

                        SizedBox(
                          width: double.infinity,
                          child: TextField(
                            controller: _emailController,
                            enabled: !_forcePasswordReset,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),

                        const SizedBox(height: verticalSpacing),

                        if (!_forcePasswordReset) ...[
                          SizedBox(
                            width: double.infinity,
                            child: TextField(
                              controller: _passwordController,
                              obscureText: true,
                              onSubmitted: (_) => _handleLogin(),
                              decoration: const InputDecoration(
                                labelText: 'Password',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          GestureDetector(
                            onTap: _canSendReset ? _sendPasswordReset : null,
                            child: Text(
                              'Forgot password?',
                              style: TextStyle(
                                color: _canSendReset
                                    ? BrandColors.lightBlue
                                    : Colors.grey,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ] else ...[
                          SizedBox(
                            width: double.infinity,
                            child: TextField(
                              controller: _newPasswordController,
                              obscureText: true,
                              decoration: const InputDecoration(
                                labelText: 'New Password',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),

                          const SizedBox(height: verticalSpacing),

                          SizedBox(
                            width: double.infinity,
                            child: TextField(
                              controller: _confirmPasswordController,
                              obscureText: true,
                              onSubmitted: (_) => _handlePasswordReset(),
                              decoration: const InputDecoration(
                                labelText: 'Confirm Password',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],

                        const SizedBox(height: verticalSpacing),

                        if (_errorMessage != null)
                          Text(_errorMessage!,
                              style: const TextStyle(color: Colors.red)),

                        if (_infoMessage != null)
                          Text(_infoMessage!,
                              style: const TextStyle(color: Colors.green)),

                        const SizedBox(height: verticalSpacing),

                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: BrandColors.lightBlue,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: _isLoading
                                ? null
                                : (_forcePasswordReset
                                    ? _handlePasswordReset
                                    : _handleLogin),
                            child: _isLoading
                                ? const CircularProgressIndicator()
                                : Text(_forcePasswordReset
                                    ? 'Reset Password'
                                    : 'Login'),
                          ),
                        ),
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
