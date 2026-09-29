import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:talksy/screens/auth/entryscreen.dart';

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

class _ShowDetailScreenState extends State<ShowDetailScreen> {
  final TextEditingController _otpController = TextEditingController();
  bool _isOtpSent = false;
  bool _isLoading = false;
  String? _generatedOtp;
  DateTime? _otpExpiry;
  int _resendAttempts = 0;

  String _generateOtp() {
    return List<int>.generate(6, (_) => Random.secure().nextInt(10)).join();
  }

  Future<String?> _sendEmailOtp(String email, String otp) async {
    final apiKey = dotenv.env['BREVO_API_KEY'];
    final mailFrom = dotenv.env['MAIL_FROM'];
    final mailFromName = dotenv.env['MAIL_FROM_NAME'] ?? 'Talksy';

    if (apiKey == null ||
        apiKey.isEmpty ||
        mailFrom == null ||
        mailFrom.isEmpty) {
      return 'Missing BREVO_API_KEY or MAIL_FROM in .env';
    }

    if (apiKey.startsWith('xsmtpsib-')) {
      return 'BREVO_API_KEY is an SMTP key. Generate an API key (starts with xkeysib-) from Brevo → SMTP & API → API keys & MCP';
    }

    final htmlContent =
        '''
<!DOCTYPE html>
<html lang="en">
<body style="margin:0;padding:48px 16px;background:#f6f7f9;font-family:Arial,sans-serif;color:#171717;text-align:center;">
  <div style="max-width:560px;margin:0 auto;background:#ffffff;border:1px solid #e7e8eb;border-radius:12px;padding:30px 36px;">
    <h2 style="margin:0 0 20px;font-size:22px;border-bottom:1px solid #eeeeef;padding-bottom:20px;">Talksy</h2>
    <h1 style="font-size:25px;margin:0 0 14px;">Verify your email address</h1>
    <p style="font-size:15px;color:#62666d;margin:0 0 30px;">Thanks for creating your Talksy account. Enter the verification code below.</p>
    <div style="background:#f8f9fb;border:1px solid #e4e6ea;border-radius:10px;padding:24px;margin-bottom:30px;">
      <div style="font-size:11px;font-weight:600;letter-spacing:1.5px;color:#858a92;margin-bottom:12px;">VERIFICATION CODE</div>
      <div style="font-size:32px;font-weight:700;letter-spacing:7px;">$otp</div>
    </div>
    <p style="font-size:13px;color:#777c84;margin:0 0 30px;">This code will expire in <strong>10 minutes</strong>.</p>
    <p style="font-size:11px;color:#b0b4ba;border-top:1px solid #eeeeef;padding-top:20px;margin:0;">© 2026 Talksy. Automated security email.</p>
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
          "sender": {"name": mailFromName, "email": mailFrom},
          "to": [
            {"email": email},
          ],
          "subject": "Your Talksy verification code",
          "htmlContent": htmlContent,
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return null;
      }

      String detail = response.body;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['message'] != null) {
          detail = decoded['message'].toString();
        }
      } catch (_) {}

      return 'Brevo API error (${response.statusCode}): $detail';
    } catch (e) {
      return 'Network error: $e';
    }
  }

  Future<String?> _uploadImageToCloudinary() async {
    if (widget.profileImage == null) return null;
    final cloudName = dotenv.env['CLOUDINARY_CLOUD_NAME'];
    final uploadPreset = dotenv.env['CLOUDINARY_UPLOAD_PRESET'];
    if (cloudName == null || uploadPreset == null) return null;

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload'),
      );
      request.fields['upload_preset'] = uploadPreset;
      request.files.add(
        await http.MultipartFile.fromPath('file', widget.profileImage!.path),
      );

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

  Future<void> _sendVerificationCode() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final otp = _generateOtp();
      final error = await _sendEmailOtp(widget.email.trim(), otp);

      if (error == null) {
        setState(() {
          _generatedOtp = otp;
          _otpExpiry = DateTime.now().add(const Duration(minutes: 10));
          _isOtpSent = true;
        });
        _showSnack('Verification code sent to your email.');
      } else {
        _showSnack(error);
      }
    } catch (_) {
      _showSnack('Error sending verification code.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyAndCreateAccount() async {
    if (_isLoading) return;

    final token = _otpController.text.trim();
    if (token.length != 6) return _showSnack('Enter a 6 digit code.');
    if (_generatedOtp == null || _otpExpiry == null) {
      return _showSnack('No code generated. Please request a code.');
    }
    if (DateTime.now().isAfter(_otpExpiry!)) {
      return _showSnack('Code expired. Please resend.');
    }
    if (token != _generatedOtp) {
      return _showSnack('Invalid verification code. Please try again.');
    }

    setState(() => _isLoading = true);

    try {
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

      if (res.user == null) throw Exception('Sign up failed.');

      _showSnack('Account created successfully.');

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          CupertinoPageRoute(
            builder: (_) => const EntryScreen(showSuccessPopup: true),
          ),
          (route) => false,
        );
      }
    } on AuthException catch (e) {
      _showSnack(e.message);
    } catch (_) {
      _showSnack('Error creating account.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Widget _buildInfoRow(String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ),
          Container(
            width: 1,
            height: 14,
            color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
            margin: const EdgeInsets.symmetric(horizontal: 10),
          ),
          Expanded(
            flex: 6,
            child: Text(
              value,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = Theme.of(context).cardColor;
    final disabledBg = isDark ? Colors.grey.shade700 : Colors.grey.shade300;
    final disabledFg = isDark ? Colors.grey.shade400 : Colors.grey.shade600;

    final isVerifyEnabled =
        !_isLoading && _otpController.text.trim().length == 6;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        toolbarHeight: 40,
        leading: const BackButton(),
        titleSpacing: 0,
        title: const Text('Review & Verify'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFFC0C0C0),
                        width: 2.0,
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 28,
                      backgroundColor: Colors.grey.shade200,
                      backgroundImage: widget.profileImage != null
                          ? FileImage(widget.profileImage!)
                          : null,
                      child: widget.profileImage == null
                          ? Icon(
                              Icons.person,
                              size: 25,
                              color: Colors.grey.shade500,
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 12,
                      ),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        children: [
                          _buildInfoRow(
                            'Name',
                            '${widget.firstName} ${widget.lastName}',
                            isDark,
                          ),
                          _buildInfoRow(
                            'Birthday',
                            DateFormat('MMMM dd, yyyy').format(widget.dob),
                            isDark,
                          ),
                          _buildInfoRow('Gender', widget.gender, isDark),
                          _buildInfoRow('Email', widget.email, isDark),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              if (!_isOtpSent) ...[
                const Text(
                  "Everything looks good? Let's verify your email to finish setting up your account.",
                  style: TextStyle(fontSize: 15),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _sendVerificationCode,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isLoading
                          ? disabledBg
                          : AppTheme.primary,
                      foregroundColor: _isLoading ? disabledFg : Colors.white,
                      disabledBackgroundColor: disabledBg,
                      disabledForegroundColor: disabledFg,
                      elevation: 0,
                      shadowColor: Colors.transparent,
                      surfaceTintColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _isLoading
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: disabledFg,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Send Verification Code',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ] else ...[
                const Text(
                  'Enter Verification Code',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  'We sent a code to your email. Please enter it below.',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: 140,
                  child: TextField(
                    controller: _otpController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 6,
                    style: const TextStyle(fontSize: 20, letterSpacing: 8),
                    decoration: InputDecoration(
                      hintText: '000000',
                      counterText: '',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: cardColor,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: isVerifyEnabled ? _verifyAndCreateAccount : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isVerifyEnabled
                          ? AppTheme.primary
                          : disabledBg,
                      foregroundColor: isVerifyEnabled
                          ? Colors.white
                          : disabledFg,
                      disabledBackgroundColor: disabledBg,
                      disabledForegroundColor: disabledFg,
                      elevation: 0,
                      shadowColor: Colors.transparent,
                      surfaceTintColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _isLoading
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: disabledFg,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Verify & Create Account',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: TextButton(
                    onPressed: _isLoading
                        ? null
                        : () {
                            if (_resendAttempts >= 3) {
                              _showSnack('Maximum resend attempts reached.');
                            } else {
                              _resendAttempts++;
                              _sendVerificationCode();
                            }
                          },
                    child: const Text('Resend code'),
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
