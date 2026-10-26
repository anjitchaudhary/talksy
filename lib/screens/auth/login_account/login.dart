import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthApiException, User;
import 'package:talksy/api_gateway.dart';
import 'package:talksy/local_db.dart';
import 'package:talksy/screens/auth/entryscreen.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'home/home.dart';

ApiGateway get _api => ApiGateway.instance;

final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

const int _maxEmailLength = 180;

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
  static Future<User?> signIn({String? expectedEmail}) async {
    final identity = await _api.pickGoogleAccount();
    if (identity == null) return null;

    final email = identity.email.trim().toLowerCase();
    if (expectedEmail != null && email != expectedEmail.toLowerCase()) {
      await _api.releaseGoogleAccount();
      throw _GoogleLoginException('Please sign in with $expectedEmail.');
    }

    if (!await _api.emailExists(email)) {
      await _api.releaseGoogleAccount();
      throw const _GoogleLoginException('This email is not registered.');
    }

    return _api.signInWithGoogle(identity.idToken);
  }

  static String messageFor(Object error, {required String fallback}) {
    if (error is GatewayException && error.code == 'rate_limited') {
      return 'Too many attempts. Please wait a minute and try again.';
    }
    if (error is GatewayException && error.code.startsWith('google')) {
      return 'Google sign in failed. Please try again.';
    }
    if (error is GatewayException && error.code.startsWith('captcha')) {
      return 'Captcha verification failed. Please try again.';
    }
    if (error is _GoogleLoginException) return error.message;
    return fallback;
  }
}

class SavedAccountStore {
  static const FlutterSecureStorage _vault = FlutterSecureStorage();
  static final LocalDb _db = LocalDb.instance;

  static String _vaultKey(String id) => 'account_password_$id';

  static Future<List<Map<String, dynamic>>> load() => _db.savedAccounts();

  static Future<String?> password(String id) {
    return _vault.read(key: _vaultKey(id));
  }

  static Future<String> _cacheAvatar(String url, String userId) async {
    if (url.isEmpty) return '';
    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return '';
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/avatar_$userId.jpg');
      await file.writeAsBytes(response.bodyBytes);
      return file.path;
    } catch (_) {
      return '';
    }
  }

  static Future<void> save({required User user, String? password}) async {
    try {
      final hasPassword = await _vault.containsKey(key: _vaultKey(user.id));
      if (password == null && hasPassword) {
        await _db.touchAccount(user.id);
        return;
      }

      final meta = user.userMetadata ?? {};
      final avatarUrl = _api.avatarUrl(
        meta['profile_image'] ?? meta['avatar_url'] ?? meta['picture'],
      );

      if (password != null) {
        await _vault.write(key: _vaultKey(user.id), value: password);
      }
      await _db.saveAccount({
        'id': user.id,
        'email': (user.email ?? '').toLowerCase(),
        'provider': password == null ? 'google' : 'password',
        'first_name': (meta['first_name'] ?? meta['name'] ?? 'User').toString(),
        'last_name': (meta['last_name'] ?? '').toString(),
        'avatar_url': avatarUrl,
        'local_avatar_path': await _cacheAvatar(avatarUrl, user.id),
      });
    } catch (_) {}
  }

  static Future<void> touch(String id) async {
    try {
      await _db.touchAccount(id);
    } catch (_) {}
  }

  static Future<void> remove(String id) async {
    await _db.removeAccount(id);
    await _vault.delete(key: _vaultKey(id));
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

    if (!_emailPattern.hasMatch(email) || email.length > _maxEmailLength) {
      _showSnack('Please enter a valid email address.');
      return;
    }

    setState(() => _isAuthenticating = true);

    try {
      final token = await _LoginCaptchaDialog.show(context, email: email);
      if (token == null) return;
      await _api.verifyCaptcha(token, email: email);

      await _api.signIn(email, password);
      await _api.signOutLocal();
      if (!mounted) return;
      _openCodeSheet(email, password);
    } on AuthApiException catch (e) {
      final wrongLogin =
          e.code == 'invalid_credentials' ||
          e.message.contains('Invalid login');
      _showSnack(wrongLogin ? 'Invalid email or password.' : e.message);
    } catch (e) {
      _showSnack(
        _GoogleAuth.messageFor(e, fallback: 'Network error. Please try again.'),
      );
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
      final token = await _LoginCaptchaDialog.show(context);
      if (token == null) return;
      await _api.verifyCaptcha(token);

      final user = await _GoogleAuth.signIn();
      if (user == null) return;
      await SavedAccountStore.save(user: user);
      await _enterHome(nav, user.id);
    } catch (e) {
      await _api.releaseGoogleAccount();
      _showSnack(
        _GoogleAuth.messageFor(
          e,
          fallback: 'Sign in failed. Please try again.',
        ),
      );
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

  String _getTimeAgo(int millis) {
    final dt = DateTime.fromMillisecondsSinceEpoch(millis);
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
    final password = await SavedAccountStore.password(account['id']);
    if (password == null) throw const GatewayException('password_missing');
    return _api.signIn(account['email'], password);
  }

  Future<void> _loginToAccount(Map<String, dynamic> account) async {
    final nav = Navigator.of(context);
    final String email = account['email'];

    final token = await _LoginCaptchaDialog.show(context, email: email);
    if (token == null || !mounted) return;

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
      await _api.verifyCaptcha(token, email: email);
      final user = await _authenticate(account);
      if (user == null) {
        nav.pop();
        return;
      }

      await SavedAccountStore.touch(account['id']);
      await _enterHome(nav, user.id);
    } catch (e) {
      nav.pop();
      if (!mounted) return;
      _showError(
        _GoogleAuth.messageFor(
          e,
          fallback:
              'Saved credentials expired or invalid. Please login manually.',
        ),
      );
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
                  final timeAgo = _getTimeAgo(acc['last_login'] as int);
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

class _LoginCaptchaDialog extends StatefulWidget {
  const _LoginCaptchaDialog({required this.email});

  final String email;

  static const String siteKey = String.fromEnvironment('TURNSTILE_SITE_KEY');
  static const String origin = String.fromEnvironment('TURNSTILE_ORIGIN');

  static Future<String?> show(BuildContext context, {String email = ''}) {
    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _LoginCaptchaDialog(email: email),
    );
  }

  @override
  State<_LoginCaptchaDialog> createState() => _LoginCaptchaDialogState();
}

class _LoginCaptchaDialogState extends State<_LoginCaptchaDialog> {
  static const String action = 'login';

  String get _page {
    final siteKey = _jsLiteral(_LoginCaptchaDialog.siteKey);
    final email = widget.email.trim().toLowerCase();
    final cData = email.isEmpty
        ? ''
        : 'cData: ${_jsLiteral(base64Url.encode(utf8.encode(email)).replaceAll('=', ''))},';
    return '''
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
<style>
html, body { margin: 0; width: 100%; height: 100%; overflow: hidden; background: transparent; }
body { display: flex; align-items: center; }
#box { width: 100%; }
</style>
<script>
function initCaptcha() {
  try {
    turnstile.render('#box', {
      sitekey: $siteKey,
      action: '$action',
      $cData
      size: 'flexible',
      theme: 'auto',
      callback: function (token) { Captcha.postMessage('token:' + token); },
      'error-callback': function () { Captcha.postMessage('error'); }
    });
  } catch (e) {
    Captcha.postMessage('error');
  }
}
</script>
<script src="https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit&onload=initCaptcha"
  async defer onerror="Captcha.postMessage('error')"></script>
</head>
<body><div id="box"></div></body>
</html>
''';
  }

  static String _jsLiteral(String value) {
    return jsonEncode(value).replaceAll('<', r'\u003c');
  }

  late final WebViewController _controller;
  bool _loading = true;
  bool _failed = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel('Captcha', onMessageReceived: _onMessage)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == false || !mounted) return;
            setState(() {
              _failed = true;
              _loading = false;
            });
          },
        ),
      )
      ..loadHtmlString(_page, baseUrl: _LoginCaptchaDialog.origin);
  }

  void _onMessage(JavaScriptMessage message) {
    if (_done || !mounted) return;
    final data = message.message;
    if (data.startsWith('token:')) {
      _done = true;
      final token = data.substring(6);
      Future.delayed(const Duration(milliseconds: 700), () {
        if (mounted) Navigator.of(context).pop(token);
      });
    } else if (data == 'error') {
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  void _retry() {
    setState(() {
      _failed = false;
      _loading = true;
    });
    _controller.loadHtmlString(_page, baseUrl: _LoginCaptchaDialog.origin);
  }

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);
    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SizedBox(
          width: double.infinity,
          height: _failed ? null : 65 * textScale,
          child: _failed ? _errorCard(context) : _widget(),
        ),
      ),
    );
  }

  Widget _widget() {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: WebViewWidget(controller: _controller),
        ),
        if (_loading)
          const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2.5,
              ),
            ),
          ),
      ],
    );
  }

  Widget _errorCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Could not load the verification. Check your internet and try again.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: _retry, child: const Text('Retry')),
        ],
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
      final isValid = await _api.verifyCode(widget.email, code);

      if (isValid) {
        widget.onVerified();
        return;
      }
      if (!mounted) return;
      setState(() {
        _isVerifying = false;
        _errorMessage = 'Incorrect or expired code.';
      });
    } catch (e) {
      if (!mounted) return;
      final rateLimited = e is GatewayException && e.code == 'rate_limited';
      setState(() {
        _isVerifying = false;
        _errorMessage = rateLimited
            ? 'Too many attempts. Please wait a minute and try again.'
            : 'Verification failed. Please try again.';
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
