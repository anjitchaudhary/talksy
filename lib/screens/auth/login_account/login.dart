import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talksy/api_gateway.dart';
import 'package:talksy/screens/auth/entryscreen.dart';

import 'home/home.dart';

ApiGateway get _api => ApiGateway.instance;

final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

Future<void> _enterHome(NavigatorState nav, String userId) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('otp_verified_$userId', true);

  nav.pushAndRemoveUntil(
    CupertinoPageRoute(
      builder: (_) => const HomeScreen(showSuccessPopup: false),
    ),
    (route) => false,
  );
}

class _GoogleLoginException implements Exception {
  const _GoogleLoginException(this.message);

  final String message;
}

class _GoogleAuth {
  static Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
  }

  static Future<User> signIn({String? expectedEmail}) async {
    final account = await GoogleSignIn.instance.authenticate();
    final email = account.email.trim().toLowerCase();

    if (expectedEmail != null && email != expectedEmail.toLowerCase()) {
      await signOut();
      throw _GoogleLoginException('Please sign in with $expectedEmail.');
    }

    final registered = await _api.rpc(
      'check_email_exists',
      params: {'email_input': email},
    );
    if (registered != true) {
      await signOut();
      throw const _GoogleLoginException('This email is not registered.');
    }

    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw const AuthException('Missing Google ID token');
    }

    return _api.signInWithGoogle(idToken);
  }

  static String? messageFor(Object error, {required String fallback}) {
    if (error is GoogleSignInException) {
      debugPrint('Google error: ${error.code} | ${error.description}');
    } else {
      debugPrint('Sign in error: $error');
    }

    if (error is GoogleSignInException) {
      if (error.code == GoogleSignInExceptionCode.canceled) return null;
      return 'Google sign in failed. Please try again.';
    }
    if (error is _GoogleLoginException) return error.message;
    return fallback;
  }
}

class SavedAccountStore {
  static const String _key = 'saved_accounts';
  static const FlutterSecureStorage _vault = FlutterSecureStorage();

  static Future<List<Map<String, dynamic>>> _read() async {
    try {
      final raw = await _vault.read(key: _key);
      if (raw == null || raw.isEmpty) return [];
      return (jsonDecode(raw) as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _write(List<Map<String, dynamic>> accounts) {
    return _vault.write(key: _key, value: jsonEncode(accounts));
  }

  static Future<void> _moveOldAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    final old = prefs.getStringList(_key);
    if (old == null) return;

    final accounts = await _read();
    for (final item in old) {
      final acc = jsonDecode(item) as Map<String, dynamic>;
      final exists = accounts.any((a) => a['id'] == acc['id']);
      if (!exists) accounts.add(acc);
    }
    await _write(accounts);
    await prefs.remove(_key);
  }

  static DateTime _loginTime(Map<String, dynamic> acc) {
    return DateTime.tryParse(acc['last_login'] ?? '') ?? DateTime(2000);
  }

  static Future<String> _cacheAvatar(String url, String userId) async {
    if (url.isEmpty) return '';
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/avatar_$userId.jpg');
        await file.writeAsBytes(response.bodyBytes);
        return file.path;
      }
    } catch (_) {}
    return '';
  }

  static Future<List<Map<String, dynamic>>> load() async {
    try {
      await _moveOldAccounts();
    } catch (_) {}
    final accounts = await _read();
    accounts.sort((a, b) => _loginTime(b).compareTo(_loginTime(a)));
    return accounts;
  }

  static Future<void> save({required User user, String? password}) async {
    try {
      final accounts = await _read();
      final hasPassword = accounts.any(
        (a) => a['id'] == user.id && a['password'] != null,
      );
      if (password == null && hasPassword) {
        await touch(user.id);
        return;
      }

      final meta = user.userMetadata ?? {};
      final email = (user.email ?? '').toLowerCase();
      final avatarUrl =
          (meta['profile_image'] ?? meta['avatar_url'] ?? meta['picture'] ?? '')
              .toString();

      accounts.removeWhere((a) => a['id'] == user.id || a['email'] == email);
      accounts.add({
        'id': user.id,
        'email': email,
        'provider': password == null ? 'google' : 'password',
        'password': password,
        'first_name': (meta['first_name'] ?? meta['name'] ?? 'User').toString(),
        'last_name': (meta['last_name'] ?? '').toString(),
        'avatar_url': avatarUrl,
        'local_avatar_path': await _cacheAvatar(avatarUrl, user.id),
        'last_login': DateTime.now().toIso8601String(),
      });
      await _write(accounts);
    } catch (_) {}
  }

  static Future<void> touch(String id) async {
    final accounts = await _read();
    for (final acc in accounts) {
      if (acc['id'] == id) {
        acc['last_login'] = DateTime.now().toIso8601String();
      }
    }
    await _write(accounts);
  }

  static Future<void> remove(String id) async {
    final accounts = await _read();
    accounts.removeWhere((a) => a['id'] == id);
    await _write(accounts);
  }
}

class GoogleLogo extends StatelessWidget {
  const GoogleLogo({super.key, this.size = 24});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: const CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  const _GoogleLogoPainter();

  static const _blue = Color(0xFF4285F4);
  static const _red = Color(0xFFEA4335);
  static const _yellow = Color(0xFFFBBC05);
  static const _green = Color(0xFF34A853);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.2;
    final center = size.center(Offset.zero);
    final arcBounds = Rect.fromCircle(
      center: center,
      radius: (size.width - stroke) / 2,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;

    void drawArc(Color color, double startDegrees, double sweepDegrees) {
      paint.color = color;
      canvas.drawArc(
        arcBounds,
        startDegrees * math.pi / 180,
        sweepDegrees * math.pi / 180,
        false,
        paint,
      );
    }

    drawArc(_red, -150, 105);
    drawArc(_yellow, 150, 60);
    drawArc(_green, 45, 105);
    drawArc(_blue, 0, 45);

    canvas.drawRect(
      Rect.fromLTRB(
        center.dx,
        center.dy - stroke / 2,
        size.width,
        center.dy + stroke / 2,
      ),
      Paint()..color = _blue,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();

  bool _isAuthenticating = false;
  bool _isGoogleLoading = false;
  bool _obscurePassword = true;
  bool _isButtonEnabled = false;
  bool _rememberPassword = false;

  bool get _busy => _isAuthenticating || _isGoogleLoading;

  @override
  void initState() {
    super.initState();
    _emailCtrl.addListener(_validateInput);
    _passCtrl.addListener(_validateInput);
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _validateInput() {
    final isValid =
        _emailCtrl.text.trim().isNotEmpty && _passCtrl.text.isNotEmpty;
    if (_isButtonEnabled != isValid) {
      setState(() => _isButtonEnabled = isValid);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showInfoDialog(BuildContext context) {
    showCupertinoDialog(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Login Methods Guide'),
        content: const Padding(
          padding: EdgeInsets.only(top: 10.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '1. Standard Login:\nSign in using your Email & Password. For enhanced security, a 2-Step Verification code generated via the Talksy Authenticator app must be entered within 60 seconds.',
                textAlign: TextAlign.justify,
                style: TextStyle(fontSize: 13, height: 1.35),
              ),
              SizedBox(height: 10),
              Text(
                '2. Direct Google Sign-In:\nAlternatively, use Google Sign-In for seamless access. If you ever forget your password, you can sign in directly through Google.',
                textAlign: TextAlign.justify,
                style: TextStyle(fontSize: 13, height: 1.35),
              ),
            ],
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Future<void> _onAuthenticate() async {
    FocusScope.of(context).unfocus();
    final email = _emailCtrl.text.trim().toLowerCase();
    final password = _passCtrl.text;

    if (!_emailPattern.hasMatch(email)) {
      _showSnack('Please enter a valid email address.');
      return;
    }

    setState(() => _isAuthenticating = true);

    try {
      await _api.signIn(email, password);
      await _api.signOutLocal();
      if (!mounted) return;
      _openCodeSheet(email, password);
    } on AuthApiException catch (e) {
      final wrongLogin =
          e.code == 'invalid_credentials' ||
          e.message.contains('Invalid login');
      _showSnack(wrongLogin ? 'Invalid email or password.' : e.message);
    } catch (_) {
      _showSnack('Network error. Please try again.');
    } finally {
      if (mounted) setState(() => _isAuthenticating = false);
    }
  }

  void _openCodeSheet(String email, String password) {
    final nav = Navigator.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: _OtpBottomSheetWidget(
          email: email,
          onCancel: () => Navigator.pop(sheetContext),
          onVerified: () {
            Navigator.pop(sheetContext);
            _signInWithPassword(nav, email, password);
          },
        ),
      ),
    );
  }

  Future<void> _signInWithPassword(
    NavigatorState nav,
    String email,
    String password,
  ) async {
    setState(() => _isAuthenticating = true);

    try {
      final user = await _api.signIn(email, password);

      if (_rememberPassword) {
        await SavedAccountStore.save(user: user, password: password);
      }
      await _enterHome(nav, user.id);
    } catch (_) {
      _showSnack('Sign in failed. Please generate a new code and try again.');
    } finally {
      if (mounted) setState(() => _isAuthenticating = false);
    }
  }

  Future<void> _onGoogleSignIn() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    final nav = Navigator.of(context);
    setState(() => _isGoogleLoading = true);

    try {
      final user = await _GoogleAuth.signIn();
      await SavedAccountStore.save(user: user);
      await _enterHome(nav, user.id);
    } catch (e) {
      await _GoogleAuth.signOut();
      final message = _GoogleAuth.messageFor(
        e,
        fallback: 'Sign in failed. Please try again.',
      );
      if (message != null) _showSnack(message);
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final disabledBg = isDark ? Colors.grey.shade700 : Colors.grey.shade300;
    final disabledFg = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    final canSubmit = _isButtonEnabled && !_busy;
    final primary = AppTheme.primary;
    final textColor = isDark ? Colors.white : Colors.black87;
    final mutedColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    final lineColor = isDark ? Colors.grey.shade800 : Colors.grey.shade300;

    return Scaffold(
      backgroundColor: bg,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        toolbarHeight: 40,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, size: 20, color: textColor),
          onPressed: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              Navigator.pushReplacement(
                context,
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) =>
                      const EntryScreen(),
                  transitionsBuilder:
                      (context, animation, secondaryAnimation, child) {
                        const begin = Offset(-1.0, 0.0);
                        const end = Offset.zero;
                        final curve = Curves.easeInOut;
                        final tween = Tween(
                          begin: begin,
                          end: end,
                        ).chain(CurveTween(curve: curve));
                        final offsetAnimation = animation.drive(tween);
                        return SlideTransition(
                          position: offsetAnimation,
                          child: child,
                        );
                      },
                ),
              );
            }
          },
        ),
        titleSpacing: 0,
        title: const Text(
          'Log In',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.info_outline, size: 22, color: textColor),
            onPressed: () => _showInfoDialog(context),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
                  const SizedBox(height: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            height: 24,
                            width: 24,
                            child: Checkbox(
                              value: _rememberPassword,
                              onChanged: (val) {
                                setState(() {
                                  _rememberPassword = val ?? false;
                                });
                              },
                              activeColor: primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _rememberPassword = !_rememberPassword;
                              });
                            },
                            child: Text(
                              'Remember password',
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark ? Colors.white70 : Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Padding(
                        padding: const EdgeInsets.only(left: 32),
                        child: Text(
                          'When you check this option, your account will be saved on talksy and you don\'t need to enter password and verify code again to re-login.',
                          style: TextStyle(fontSize: 11, color: mutedColor),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: canSubmit ? _onAuthenticate : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: canSubmit ? primary : disabledBg,
                        foregroundColor: canSubmit ? Colors.white : disabledFg,
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
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.shield_outlined, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'Authenticate',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: Divider(color: lineColor)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'Or',
                          style: TextStyle(fontSize: 14, color: mutedColor),
                        ),
                      ),
                      Expanded(child: Divider(color: lineColor)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton(
                      onPressed: _busy ? null : _onGoogleSignIn,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: textColor,
                        side: BorderSide(color: lineColor, width: 1.2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _isGoogleLoading
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: primary,
                                  ),
                                )
                              : const GoogleLogo(size: 20),
                          const SizedBox(width: 12),
                          Text(
                            _isGoogleLoading
                                ? 'Signing in...'
                                : 'Sign in with Google',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 20,
              bottom: 20,
              child: SizedBox(
                width: 50,
                height: 50,
                child: FloatingActionButton(
                  backgroundColor: primary,
                  foregroundColor: Colors.white,
                  elevation: 6,
                  onPressed: () {
                    Navigator.push(
                      context,
                      CupertinoPageRoute(
                        builder: (_) => const SavedAccountScreen(),
                      ),
                    );
                  },
                  child: const Icon(Icons.manage_accounts_outlined, size: 28),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SavedAccountScreen extends StatefulWidget {
  const SavedAccountScreen({super.key});

  @override
  State<SavedAccountScreen> createState() => _SavedAccountScreenState();
}

class _SavedAccountScreenState extends State<SavedAccountScreen> {
  List<Map<String, dynamic>> _savedAccounts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSavedAccounts();
  }

  Future<void> _loadSavedAccounts() async {
    final accounts = await SavedAccountStore.load();
    if (!mounted) return;
    setState(() {
      _savedAccounts = accounts;
      _isLoading = false;
    });
  }

  String _getTimeAgo(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return 'Unknown';
    final dt = DateTime.tryParse(timeStr);
    if (dt == null) return 'Unknown';
    final diff = DateTime.now().difference(dt);

    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  void _deleteAccount(String id) {
    showCupertinoDialog(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Are you sure to remove this saved account?'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () async {
              Navigator.pop(dialogContext);
              await SavedAccountStore.remove(id);
              if (!mounted) return;
              setState(() {
                _savedAccounts.removeWhere((acc) => acc['id'] == id);
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Account removed successfully.'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            child: const Text('Yes'),
          ),
        ],
      ),
    );
  }

  Future<User?> _authenticate(Map<String, dynamic> account) async {
    if (account['provider'] == 'google') {
      return _GoogleAuth.signIn(expectedEmail: account['email']);
    }
    return _api.signIn(account['email'], account['password']);
  }

  Future<void> _loginToAccount(Map<String, dynamic> account) async {
    final nav = Navigator.of(context);

    showCupertinoDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const CupertinoAlertDialog(
        content: Padding(
          padding: EdgeInsets.all(16.0),
          child: CupertinoActivityIndicator(radius: 14),
        ),
      ),
    );

    try {
      final user = await _authenticate(account);
      if (user == null) throw const AuthException('No user returned');

      await SavedAccountStore.touch(account['id']);
      await _enterHome(nav, user.id);
    } catch (e) {
      nav.pop();
      final message = _GoogleAuth.messageFor(
        e,
        fallback:
            'Saved credentials expired or invalid. Please login manually.',
      );
      if (message != null && mounted) _showError(message);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = Theme.of(context).scaffoldBackgroundColor;
    final textColor = isDark ? Colors.white : Colors.black87;
    final cardBg = Theme.of(context).cardColor;
    final borderColor = isDark
        ? const Color(0xFF2C2C2E)
        : const Color(0xFFE5E5EA);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(40),
        child: AppBar(
          backgroundColor: bgColor,
          elevation: 0,
          automaticallyImplyLeading: false,
          titleSpacing: 0,
          title: SafeArea(
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(32, 32),
                    onPressed: () => Navigator.pop(context),
                    child: Icon(
                      Icons.arrow_back_ios_new,
                      size: 20,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Saved accounts',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CupertinoActivityIndicator())
            : _savedAccounts.isEmpty
            ? Center(
                child: Text(
                  'No saved accounts found',
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _savedAccounts.length,
                itemBuilder: (context, index) {
                  final acc = _savedAccounts[index];
                  final firstName = acc['first_name'] ?? '';
                  final lastName = acc['last_name'] ?? '';
                  final fullName = '$firstName $lastName'.trim();
                  final displayName = fullName.isEmpty
                      ? acc['email']
                      : fullName;
                  final localAvatarPath = acc['local_avatar_path'] ?? '';
                  final avatarUrl = acc['avatar_url'] ?? '';
                  final timeAgo = _getTimeAgo(acc['last_login']);
                  final viaGoogle = acc['provider'] == 'google';

                  Widget avatarWidget;
                  if (localAvatarPath.isNotEmpty &&
                      File(localAvatarPath).existsSync()) {
                    avatarWidget = Image.file(
                      File(localAvatarPath),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Icon(
                        Icons.person,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    );
                  } else if (avatarUrl.isNotEmpty) {
                    avatarWidget = Image.network(
                      avatarUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Icon(
                        Icons.person,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    );
                  } else {
                    avatarWidget = Icon(
                      Icons.person,
                      color: isDark ? Colors.white70 : Colors.black54,
                    );
                  }

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: borderColor, width: 0.5),
                    ),
                    child: CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => _loginToAccount(acc),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            ClipOval(
                              child: Container(
                                width: 48,
                                height: 48,
                                color: isDark
                                    ? Colors.grey.shade800
                                    : Colors.grey.shade200,
                                child: avatarWidget,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    displayName,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: textColor,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    viaGoogle
                                        ? 'Last login: $timeAgo  •  Google'
                                        : 'Last login: $timeAgo',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark
                                          ? Colors.grey.shade400
                                          : Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            CupertinoButton(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(32, 32),
                              onPressed: () => _deleteAccount(acc['id']),
                              child: const Icon(
                                Icons.delete_outline,
                                color: Colors.redAccent,
                                size: 20,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _OtpBottomSheetWidget extends StatefulWidget {
  final String email;
  final VoidCallback onCancel;
  final VoidCallback onVerified;

  const _OtpBottomSheetWidget({
    required this.email,
    required this.onCancel,
    required this.onVerified,
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

  Future<void> _verifyCode() async {
    final code = _otpCtrl.text.trim();
    if (code.length != 6) {
      setState(() => _errorMessage = 'Please enter a valid 6-digit code.');
      return;
    }

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    try {
      final isValid = await _api.rpc(
        'verify_code_for_email',
        params: {'p_email': widget.email, 'p_code': code},
      );

      if (isValid == true) {
        widget.onVerified();
        return;
      }
      if (!mounted) return;
      setState(() {
        _isVerifying = false;
        _errorMessage = 'Incorrect or expired code.';
      });
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
    final borderColor = isDark ? Colors.grey.shade700 : Colors.grey.shade300;

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
                  color: borderColor,
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
                  'Log in to the Talksy authenticator app with ${widget.email} and enter the generated 6-digit code shown there within 60 seconds.',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _otpCtrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
                    borderSide: BorderSide(color: borderColor, width: 1),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: primary, width: 1.2),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: borderColor, width: 1),
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
                    onPressed: _isVerifying ? null : widget.onCancel,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 0,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Cancel',
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
                  onPressed: _isVerifying ? null : _verifyCode,
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
