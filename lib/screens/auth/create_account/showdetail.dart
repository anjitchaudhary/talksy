import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talksy/screens/auth/entryscreen.dart';
import 'package:talksy/screens/auth/login_account/home/home.dart';

class ShowDetailScreen extends StatefulWidget {
  final String firstName;
  final String lastName;
  final File? profileImage;
  final DateTime dob;
  final String gender;
  final String email;
  final String password;

  const ShowDetailScreen({
    super.key,
    required this.firstName,
    required this.lastName,
    this.profileImage,
    required this.dob,
    required this.gender,
    required this.email,
    required this.password,
  });

  static Route route({
    required String firstName,
    required String lastName,
    File? profileImage,
    required DateTime dob,
    required String gender,
    required String email,
    required String password,
  }) {
    return CupertinoPageRoute(
      builder: (_) => ShowDetailScreen(
        firstName: firstName,
        lastName: lastName,
        profileImage: profileImage,
        dob: dob,
        gender: gender,
        email: email,
        password: password,
      ),
    );
  }

  @override
  State<ShowDetailScreen> createState() => _ShowDetailScreenState();
}

class _ShowDetailScreenState extends State<ShowDetailScreen> with WidgetsBindingObserver {
  final TextEditingController _otpController = TextEditingController();
  
  bool _isOtpSent = false;
  bool _isLoading = false;
  DateTime? _otpExpiry;
  DateTime? _resendAvailableAt;
  Timer? _timer;
  int _secondsRemaining = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncBackendStatus();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateTimer());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _otpController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isOtpSent) {
      _syncBackendStatus();
    }
  }

  Future<void> _syncBackendStatus() async {
    try {
      final res = await Supabase.instance.client.rpc(
        'get_otp_status',
        params: {'p_email': widget.email},
      );
      if (res != null && res['exists'] == true) {
        if (mounted) {
          setState(() {
            _otpExpiry = DateTime.parse(res['expires_at']).toLocal();
            _resendAvailableAt = DateTime.parse(res['last_sent_at']).toLocal().add(const Duration(minutes: 10));
            
            final diff = _resendAvailableAt!.difference(DateTime.now()).inSeconds;
            _secondsRemaining = diff > 0 ? diff : 0;
            _isOtpSent = true;
          });
        }
      } else {
        if (_isOtpSent && mounted) setState(() => _isOtpSent = false);
      }
    } catch (_) {}
  }

  void _updateTimer() {
    if (_otpExpiry != null && DateTime.now().isAfter(_otpExpiry!)) {
      if (_isOtpSent && mounted) setState(() => _isOtpSent = false);
      return;
    }
    if (_resendAvailableAt == null) {
      if (_secondsRemaining != 0 && mounted) setState(() => _secondsRemaining = 0);
      return;
    }
    final diff = _resendAvailableAt!.difference(DateTime.now()).inSeconds;
    final newSeconds = diff > 0 ? diff : 0;
    if (_secondsRemaining != newSeconds && mounted) {
      setState(() => _secondsRemaining = newSeconds);
    }
  }

  Future<String?> _sendEmailOtp(String email, String otp) async {
    final apiKey = dotenv.env['BREVO_API_KEY'];
    final mailFrom = dotenv.env['MAIL_FROM'];
    if (apiKey == null || mailFrom == null) return 'Configuration error';

    final htmlContent = '''
<!DOCTYPE html>
<html lang="en">
<body style="margin:0;padding:48px 16px;background:#f6f7f9;font-family:Arial,sans-serif;color:#171717;text-align:center;">
  <div style="max-width:560px;margin:0 auto;background:#ffffff;border:1px solid #e7e8eb;border-radius:12px;padding:30px 36px;">
    <h2 style="margin:0 0 20px;font-size:22px;border-bottom:1px solid #eeeeef;padding-bottom:20px;">Talksy</h2>
    <h1 style="font-size:25px;margin:0 0 14px;">Verify your email address</h1>
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
          'content-type': 'application/json'
        },
        body: jsonEncode({
          "sender": {"name": "Talksy", "email": mailFrom},
          "to": [{"email": email}],
          "subject": "Your Talksy verification code",
          "htmlContent": htmlContent
        }),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) return null;
      return 'API transmission error';
    } catch (_) {
      return 'Network connection error';
    }
  }

  Future<String?> _uploadImageToCloudinary() async {
    if (widget.profileImage == null) return null;
    final cloudName = dotenv.env['CLOUDINARY_CLOUD_NAME'];
    final uploadPreset = dotenv.env['CLOUDINARY_UPLOAD_PRESET'];
    if (cloudName == null || uploadPreset == null) return null;

    try {
      final request = http.MultipartRequest('POST', Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload'));
      request.fields['upload_preset'] = uploadPreset;
      request.files.add(await http.MultipartFile.fromPath('file', widget.profileImage!.path));

      final response = await request.send();
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final resData = jsonDecode(await response.stream.bytesToString());
        return resData['secure_url'] as String?;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _handleSendCode() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final res = await Supabase.instance.client.rpc(
        'get_otp_status',
        params: {'p_email': widget.email.trim()},
      );
      
      if (res != null && res['exists'] == true) {
        setState(() {
          _otpExpiry = DateTime.parse(res['expires_at']).toLocal();
          _resendAvailableAt = DateTime.parse(res['last_sent_at']).toLocal().add(const Duration(minutes: 10));
          
          final diff = _resendAvailableAt!.difference(DateTime.now()).inSeconds;
          _secondsRemaining = diff > 0 ? diff : 0;
          _isOtpSent = true;
        });
        _showSnack('Active verification code already exists.');
      } else {
        final otp = List<int>.generate(6, (_) => Random.secure().nextInt(10)).join();
        final error = await _sendEmailOtp(widget.email.trim(), otp);

        if (error == null) {
          await Supabase.instance.client.rpc(
            'store_otp',
            params: {'p_email': widget.email.trim(), 'p_otp': otp},
          );
          await _syncBackendStatus();
          _showSnack('Verification code sent successfully.');
        } else {
          _showSnack(error);
        }
      }
    } catch (_) {
      _showSnack('Failed to process verification request.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyAndCreateAccount() async {
    if (_isLoading) return;
    final token = _otpController.text.trim();
    if (token.length != 6) return _showSnack('Enter a valid 6-digit code.');
    if (_otpExpiry == null || DateTime.now().isAfter(_otpExpiry!)) return _showSnack('Code has expired. Request a new one.');

    setState(() => _isLoading = true);

    try {
      final isValid = await Supabase.instance.client.rpc(
        'verify_otp',
        params: {'p_email': widget.email.trim(), 'p_otp': token},
      );
      
      if (isValid != true) {
        _showSnack('Invalid verification code.');
        setState(() => _isLoading = false);
        return;
      }

      final imageUrl = await _uploadImageToCloudinary();
      final fullName = '${widget.firstName.trim()} ${widget.lastName.trim()}';

      final res = await Supabase.instance.client.auth.signUp(
        email: widget.email.trim(),
        password: widget.password,
        data: {
          'first_name': widget.firstName.trim(),
          'last_name': widget.lastName.trim(),
          'display_name': fullName,
          'full_name': fullName,
          'dob': widget.dob.toIso8601String(),
          'gender': widget.gender,
          'profile_image': imageUrl,
          'avatar_url': imageUrl,
        },
      );

      if (res.user == null) throw Exception('Authentication signup failed.');

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('otp_verified_${res.user!.id}', true);

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          CupertinoPageRoute(builder: (_) => const HomeScreen(showSuccessPopup: true)),
          (route) => false,
        );
      }
    } catch (_) {
      _showSnack('Error occurred during account creation.');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void _showDetailPopup() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final textColor = Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black;
        return Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(context).padding.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'User Details',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: textColor),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  const Icon(Icons.cake_outlined, size: 28, color: Colors.grey),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Date of Birth', style: TextStyle(fontSize: 14, color: Colors.grey)),
                      Text(
                        DateFormat('MMMM dd, yyyy').format(widget.dob), 
                        style: TextStyle(fontSize: 16, color: textColor, fontWeight: FontWeight.w500)
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Icon(Icons.person_outline, size: 28, color: Colors.grey),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Gender', style: TextStyle(fontSize: 14, color: Colors.grey)),
                      Text(
                        widget.gender, 
                        style: TextStyle(fontSize: 16, color: textColor, fontWeight: FontWeight.w500)
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Icon(Icons.lock_outline, size: 28, color: Colors.grey),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Password', style: TextStyle(fontSize: 14, color: Colors.grey)),
                      Text(
                        widget.password, 
                        style: TextStyle(fontSize: 16, color: textColor, fontWeight: FontWeight.w500)
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = Theme.of(context).cardColor;
    final disabledBg = isDark ? Colors.grey.shade700 : Colors.grey.shade300;
    final disabledFg = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    
    final isVerifyEnabled = !_isLoading && _otpController.text.trim().length == 6;
    final canResend = _secondsRemaining == 0;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        toolbarHeight: 40,
        leading: const BackButton(),
        titleSpacing: 0,
        title: const Text('Review & Verify'),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: _showDetailPopup,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFC0C0C0), width: 1.5),
                    ),
                    child: CircleAvatar(
                      radius: 28,
                      backgroundColor: Colors.transparent,
                      backgroundImage: widget.profileImage != null ? FileImage(widget.profileImage!) : null,
                      child: widget.profileImage == null ? Icon(Icons.person, size: 25, color: Colors.grey.shade500) : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${widget.firstName} ${widget.lastName}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text(widget.email, style: const TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              
              if (!_isOtpSent) ...[
                const Text("Verify your email address to complete your registration.", style: TextStyle(fontSize: 15)),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleSendCode,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isLoading ? disabledBg : AppTheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _isLoading 
                        ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: disabledFg, strokeWidth: 2)) 
                        : const Text('Send Verification Code'),
                  ),
                ),
              ] else ...[
                const Text('Enter Verification Code', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                TextField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 6,
                  style: const TextStyle(fontSize: 20, letterSpacing: 8),
                  decoration: InputDecoration(
                    hintText: '000000',
                    counterText: '',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: cardColor,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: isVerifyEnabled ? _verifyAndCreateAccount : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isVerifyEnabled ? AppTheme.primary : disabledBg,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _isLoading 
                        ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: disabledFg, strokeWidth: 2)) 
                        : const Text('Verify & Create Account'),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: TextButton(
                    onPressed: _isLoading ? null : () async {
                      if (!canResend) {
                        _showSnack('Please wait before requesting a new code.');
                        return;
                      }
                      
                      setState(() => _isLoading = true);
                      final otp = List<int>.generate(6, (_) => Random.secure().nextInt(10)).join();
                      final err = await _sendEmailOtp(widget.email, otp);
                      
                      if (err == null) {
                        await Supabase.instance.client.rpc(
                          'store_otp',
                          params: {'p_email': widget.email, 'p_otp': otp},
                        );
                        await _syncBackendStatus();
                        _showSnack('New verification code sent.');
                      } else {
                        _showSnack(err);
                      }
                      if (mounted) setState(() => _isLoading = false);
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: canResend ? AppTheme.primary : Colors.grey,
                    ),
                    child: Text(canResend ? 'Resend code' : 'Resend code in ${_secondsRemaining}s'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
