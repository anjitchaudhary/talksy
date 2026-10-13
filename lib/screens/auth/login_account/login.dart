import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talksy/screens/auth/entryscreen.dart';

import 'home/home.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with WidgetsBindingObserver {
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();

  bool _isAuthenticating = false;
  bool _obscurePassword = true;
  bool _isButtonEnabled = false;
  bool _showResumeIcon = false;

  String? _activeEmail;
  String? _activeUserId;
  DateTime? _expiresAt;
  Timer? _bgTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _emailCtrl.addListener(_validateInput);
    _passCtrl.addListener(_validateInput);
    _checkExistingSession();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _bgTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _activeEmail != null) {
      _syncBackendStatus(_activeEmail!);
    }
  }

  void _validateInput() {
    final isValid =
        _emailCtrl.text.trim().isNotEmpty && _passCtrl.text.isNotEmpty;
    if (_isButtonEnabled != isValid) {
      setState(() => _isButtonEnabled = isValid);
    }
  }

  Future<void> _checkExistingSession() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString('pending_login_email');
    final savedUserId = prefs.getString('pending_login_uid');
    final savedExpiry = prefs.getString('pending_login_expires');

    if (savedEmail != null && savedUserId != null && savedExpiry != null) {
      final expiryDate = DateTime.tryParse(savedExpiry);
      if (expiryDate != null && DateTime.now().isBefore(expiryDate)) {
        await _syncBackendStatus(
          savedEmail,
          uid: savedUserId,
          autoOpenBottomSheet: true,
        );
      } else {
        await _clearPendingSession();
      }
    }
  }

  void _startBackgroundTimer() {
    _bgTimer?.cancel();
    _bgTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_expiresAt != null && DateTime.now().isAfter(_expiresAt!)) {
        timer.cancel();
        _clearPendingSession();
      }
    });
  }

  Future<void> _clearPendingSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pending_login_email');
    await prefs.remove('pending_login_uid');
    await prefs.remove('pending_login_expires');

    if (mounted) {
      setState(() {
        _showResumeIcon = false;
        _activeEmail = null;
        _activeUserId = null;
        _expiresAt = null;
      });
    }
  }

  Future<void> _syncBackendStatus(
    String email, {
    String? uid,
    bool autoOpenBottomSheet = false,
  }) async {
    try {
      final res = await Supabase.instance.client.rpc(
        'get_otp_status',
        params: {'p_email': email},
      );

      if (res != null && res['exists'] == true) {
        final expiryStr = res['expires_at'];
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('pending_login_email', email);
        if (uid != null) await prefs.setString('pending_login_uid', uid);
        await prefs.setString('pending_login_expires', expiryStr);

        setState(() {
          _activeEmail = email;
          if (uid != null) _activeUserId = uid;
          _expiresAt = DateTime.parse(expiryStr).toLocal();
          _showResumeIcon = true;
        });

        _startBackgroundTimer();
        if (autoOpenBottomSheet) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _openOtpBottomSheet();
          });
        }
      } else {
        await _clearPendingSession();
      }
    } catch (_) {}
  }

  Future<String?> _sendEmailOtp(String email, String otp) async {
    final apiKey = dotenv.env['BREVO_API_KEY'];
    final mailFrom = dotenv.env['MAIL_FROM'];
    if (apiKey == null || mailFrom == null) return 'Configuration missing';

    final htmlContent =
        '''
<!DOCTYPE html>
<html lang="en">
<body style="margin:0;padding:48px 16px;background:#f6f7f9;font-family:Arial,sans-serif;color:#171717;text-align:center;">
  <div style="max-width:560px;margin:0 auto;background:#ffffff;border:1px solid #e7e8eb;border-radius:12px;padding:30px 36px;">
    <h2 style="margin:0 0 20px;font-size:22px;border-bottom:1px solid #eeeeef;padding-bottom:20px;">Talksy</h2>
    <h1 style="font-size:25px;margin:0 0 14px;">Log in verification</h1>
    <div style="background:#f8f9fb;border:1px solid #e4e6ea;border-radius:10px;padding:24px;margin-bottom:30px;">
      <div style="font-size:11px;font-weight:600;letter-spacing:1.5px;color:#858a92;margin-bottom:12px;">VERIFICATION CODE</div>
      <div style="font-size:32px;font-weight:700;letter-spacing:7px;">$otp</div>
    </div>
    <p style="font-size:13px;color:#777c84;margin:0 0 30px;">This code will expire in <strong>10 minutes</strong>.</p>
  </div>
</body>
</html>
''';

    try {
      final response = await http.post(
        Uri.parse('https://api.brevo.com/v3/smtp/email'),
        headers: {
          'accept': 'application/json',
          'api-key': apiKey,
          'content-type': 'application/json',
        },
        body: jsonEncode({
          "sender": {"name": "Talksy", "email": mailFrom},
          "to": [
            {"email": email},
          ],
          "subject": "Your Talksy login code",
          "htmlContent": htmlContent,
        }),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) return null;
      return 'Error sending verification code.';
    } catch (_) {
      return 'Network connection error.';
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  Future<void> _onAuthenticate() async {
    FocusScope.of(context).unfocus();
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;

    setState(() => _isAuthenticating = true);

    try {
      final res = await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: pass,
      );

      if (res.user != null) {
        final status = await Supabase.instance.client.rpc(
          'get_otp_status',
          params: {'p_email': email},
        );

        if (status != null && status['exists'] == true) {
          await _syncBackendStatus(
            email,
            uid: res.user!.id,
            autoOpenBottomSheet: true,
          );
        } else {
          final otp = List<int>.generate(
            6,
            (_) => Random.secure().nextInt(10),
          ).join();
          final error = await _sendEmailOtp(email, otp);

          if (error == null) {
            await Supabase.instance.client.rpc(
              'store_otp',
              params: {'p_email': email, 'p_otp': otp},
            );
            await _syncBackendStatus(
              email,
              uid: res.user!.id,
              autoOpenBottomSheet: true,
            );
          } else {
            _showSnack(error);
          }
        }
      }
    } catch (_) {
      _showSnack('Invalid email or password');
    } finally {
      if (mounted) setState(() => _isAuthenticating = false);
    }
  }

  void _openOtpBottomSheet() {
    if (_activeEmail == null || _activeUserId == null || _expiresAt == null) {
      return;
    }

    if (DateTime.now().isAfter(_expiresAt!)) {
      _clearPendingSession();
      return;
    }

    setState(() => _showResumeIcon = false);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: _OtpBottomSheetWidget(
          email: _activeEmail!,
          userId: _activeUserId!,
          expiresAt: _expiresAt!,
          onMinimize: () => Navigator.pop(context),
          onVerifySuccess: () async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('otp_verified_$_activeUserId', true);
            await _clearPendingSession();

            if (!mounted) return;
            // ignore: use_build_context_synchronously
            Navigator.of(context).pushAndRemoveUntil(
              CupertinoPageRoute(
                builder: (_) => const HomeScreen(showSuccessPopup: false),
              ),
              (route) => false,
            );
          },
        ),
      ),
    ).then((_) {
      if (mounted &&
          _activeEmail != null &&
          _expiresAt != null &&
          DateTime.now().isBefore(_expiresAt!)) {
        setState(() => _showResumeIcon = true);
      } else {
        _clearPendingSession();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final disabledBg = isDark ? Colors.grey.shade700 : Colors.grey.shade300;
    final disabledFg = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    final canSubmit = _isButtonEnabled && !_isAuthenticating;
    final primary = AppTheme.primary;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        toolbarHeight: 40,
        leading: const BackButton(),
        titleSpacing: 0,
        title: const Text(
          'Log In',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        actions: [
          if (_showResumeIcon)
            IconButton(
              icon: const Icon(
                Icons.mark_email_unread_outlined,
                color: Colors.blueAccent,
              ),
              onPressed: _openOtpBottomSheet,
            ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  const Text(
                    'Welcome back',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Sign in with your credentials to continue.',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      filled: true,
                      fillColor: Theme.of(context).cardColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passCtrl,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      filled: true,
                      fillColor: Theme.of(context).cardColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: _showResumeIcon
                        ? OutlinedButton.icon(
                            onPressed: _openOtpBottomSheet,
                            icon: const Icon(Icons.mark_email_unread_rounded),
                            label: const Text(
                              'Resume Verification',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: primary,
                              side: BorderSide(color: primary, width: 1.5),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          )
                        : ElevatedButton(
                            onPressed: canSubmit ? _onAuthenticate : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: canSubmit ? primary : disabledBg,
                              foregroundColor: canSubmit
                                  ? Colors.white
                                  : disabledFg,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: _isAuthenticating
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: disabledFg,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text(
                                    'Authenticate',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OtpBottomSheetWidget extends StatefulWidget {
  final String email;
  final String userId;
  final DateTime expiresAt;
  final VoidCallback onMinimize;
  final VoidCallback onVerifySuccess;

  const _OtpBottomSheetWidget({
    required this.email,
    required this.userId,
    required this.expiresAt,
    required this.onMinimize,
    required this.onVerifySuccess,
  });

  @override
  State<_OtpBottomSheetWidget> createState() => _OtpBottomSheetWidgetState();
}

class _OtpBottomSheetWidgetState extends State<_OtpBottomSheetWidget> {
  final TextEditingController _otpCtrl = TextEditingController();
  bool _isVerifying = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _otpCtrl.addListener(_onOtpChanged);
  }

  @override
  void dispose() {
    _otpCtrl.removeListener(_onOtpChanged);
    _otpCtrl.dispose();
    super.dispose();
  }

  void _onOtpChanged() {
    if (_errorMessage != null) {
      setState(() => _errorMessage = null);
    }
  }

  Future<void> _verifyOtp() async {
    final token = _otpCtrl.text.trim();
    if (token.length != 6) {
      setState(() => _errorMessage = 'Please enter a valid 6-digit code.');
      return;
    }

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    try {
      final isValid = await Supabase.instance.client.rpc(
        'verify_otp',
        params: {'p_email': widget.email, 'p_otp': token},
      );

      if (isValid == true) {
        widget.onVerifySuccess();
      } else {
        if (!mounted) return;
        setState(() {
          _isVerifying = false;
          _errorMessage = 'Incorrect or invalid verification code.';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isVerifying = false;
        _errorMessage = 'Verification failed. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = AppTheme.primary;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 28,
                height: 3.5,
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.lock_outline_rounded,
                      color: primary,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Security Verification',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Enter 6-digit code which has been sent to email: ${widget.email}',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _otpCtrl,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 6,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 10,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                decoration: InputDecoration(
                  hintText: '••••••',
                  hintStyle: TextStyle(
                    letterSpacing: 10,
                    color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
                  ),
                  counterText: '',
                  filled: true,
                  fillColor: isDark
                      ? Colors.grey.shade900
                      : Colors.grey.shade50,
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 10,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: isDark
                          ? Colors.grey.shade700
                          : Colors.grey.shade300,
                      width: 1,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: primary, width: 1.2),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: isDark
                          ? Colors.grey.shade700
                          : Colors.grey.shade300,
                      width: 1,
                    ),
                  ),
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.redAccent,
                      size: 15,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isVerifying ? null : widget.onMinimize,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 0,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Minimize',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              SizedBox(
                width: double.infinity,
                height: 45,
                child: ElevatedButton(
                  onPressed: _isVerifying ? null : _verifyOtp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: _isVerifying
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Verify & Proceed',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
