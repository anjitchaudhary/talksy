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
    return MaterialPageRoute(
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
    final rnd = Random.secure();
    return List<int>.generate(6, (_) => rnd.nextInt(10)).join();
  }

  Future<bool> _sendEmailOtp(String email, String otp) async {
    final apiKey = dotenv.env['BREVO_API_KEY'];
    final mailFrom = dotenv.env['MAIL_FROM'];
    final mailFromName = dotenv.env['MAIL_FROM_NAME'] ?? 'Talksy';

    if (apiKey == null || mailFrom == null) {
      debugPrint('BREVO_API_KEY or MAIL_FROM not configured');
      return false;
    }

    final url = Uri.parse('https://api.brevo.com/v3/smtp/email');

    final body = {
      "sender": {"name": mailFromName, "email": mailFrom},
      "to": [
        {"email": email},
      ],
      "subject": "Your Talksy verification code",
      "textContent":
          "Your verification code is $otp.\n\nIt expires in 10 minutes.",
    };

    try {
      final response = await http.post(
        url,
        headers: {
          'accept': 'application/json',
          'api-key': apiKey,
          'content-type': 'application/json',
        },
        body: jsonEncode(body),
      );

      debugPrint('Brevo status: ${response.statusCode}');
      debugPrint('Brevo body: ${response.body}');

      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e, st) {
      debugPrint('Brevo exception: $e\n$st');
      return false;
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
      final resString = await response.stream.bytesToString();
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final Map<String, dynamic> data = jsonDecode(resString);
        return data['secure_url'] as String?;
      } else {
        debugPrint('Cloudinary upload failed: $resString');
        return null;
      }
    } catch (e, st) {
      debugPrint('Cloudinary upload error: $e\n$st');
      return null;
    }
  }

  Future<void> _sendVerificationCode() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final otp = _generateOtp();
      final sent = await _sendEmailOtp(widget.email.trim(), otp);

      setState(() {
        _generatedOtp = otp;
        _otpExpiry = DateTime.now().add(const Duration(minutes: 10));
        _isOtpSent = true;
      });

      if (sent) {
        _showSnack('Verification code sent to your email.');
      } else {
        _showSnack('Unable to send email. Check SMTP/API configuration.');
      }
    } catch (e) {
      debugPrint('sendVerificationCode error: $e');
      _showSnack('Error sending verification code.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resendCode() async {
    if (_isLoading) return;
    if (_resendAttempts >= 3) {
      _showSnack('Maximum resend attempts reached.');
      return;
    }
    _resendAttempts++;
    await _sendVerificationCode();
  }

  Future<void> _verifyAndCreateAccount() async {
    if (_isLoading) return;

    final token = _otpController.text.trim();
    if (token.length != 6) {
      _showSnack('Enter a 6 digit code.');
      return;
    }
    if (_generatedOtp == null || _otpExpiry == null) {
      _showSnack('No code generated. Please request a code.');
      return;
    }
    if (DateTime.now().isAfter(_otpExpiry!)) {
      _showSnack('Code expired. Please resend.');
      return;
    }
    if (token != _generatedOtp) {
      _showSnack('Invalid code.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final String? imageUrl = await _uploadImageToCloudinary();

      final res = await Supabase.instance.client.auth.signUp(
        email: widget.email.trim(),
        password: widget.password,
        data: {
          'first_name': widget.firstName.trim(),
          'last_name': widget.lastName.trim(),
          'display_name':
              '${widget.firstName.trim()} ${widget.lastName.trim()}',
          'full_name': '${widget.firstName.trim()} ${widget.lastName.trim()}',
          'dob': widget.dob.toIso8601String(),
          'gender': widget.gender,
          'profile_image': imageUrl,
          'avatar_url': imageUrl,
        },
      );

      if (res.user == null) {
        throw Exception('Sign up failed.');
      }

      _showSnack('Account created successfully.');

      if (!mounted) return;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushAndRemoveUntil(
          CupertinoPageRoute(
            builder: (_) => const EntryScreen(showSuccessPopup: true),
          ),
          (route) => false,
        );
      });
    } on AuthException catch (e) {
      _showSnack(e.message);
    } catch (e, st) {
      debugPrint('verifyAndCreateAccount error: $e\n$st');
      _showSnack('Error creating account.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Widget _buildInfoRow(String label, String value, bool isDark) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
            ),
          ),
          Container(
            width: 1,
            color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
            margin: const EdgeInsets.symmetric(horizontal: 10),
          ),
          Expanded(
            flex: 6,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = Theme.of(context).scaffoldBackgroundColor;
    final cardColor = Theme.of(context).cardColor;

    // Theme values for buttons directly matching createname.dart
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final disabledBg = isDark ? Colors.grey.shade700 : Colors.grey.shade300;
    final disabledFg = isDark ? Colors.grey.shade400 : Colors.grey.shade600;

    // Helper bools to determine if buttons should be enabled
    final isSendEnabled = !_isLoading;
    final isVerifyEnabled =
        !_isLoading && _otpController.text.trim().length == 6;

    return Scaffold(
      backgroundColor: backgroundColor,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        elevation: 0,
        toolbarHeight: 40,
        leading: const BackButton(),
        titleSpacing: 0,
        centerTitle: false,
        title: const Text('Review & Verify', textAlign: TextAlign.left),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = constraints.maxWidth;
            final isWide = maxWidth > 600;
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 14.0,
                vertical: 16,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 32,
                ),
                child: IntrinsicHeight(
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
                                color: const Color(0xFFC0C0C0), // Silver line
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
                          const SizedBox(width: 10),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 6,
                                horizontal: 10,
                              ),
                              decoration: BoxDecoration(
                                color: cardColor,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildInfoRow(
                                    'Name',
                                    '${widget.firstName} ${widget.lastName}',
                                    isDark,
                                  ),
                                  const SizedBox(height: 4),
                                  _buildInfoRow(
                                    'Birthday',
                                    DateFormat('MMMM dd, yyyy')
                                        .format(widget.dob),
                                    isDark,
                                  ),
                                  const SizedBox(height: 4),
                                  _buildInfoRow(
                                    'Gender',
                                    widget.gender,
                                    isDark,
                                  ),
                                  const SizedBox(height: 4),
                                  _buildInfoRow('Email', widget.email, isDark),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      if (!_isOtpSent) ...[
                        Text(
                          "Everything looks good? Let's verify your email to finish setting up your account.",
                          style: TextStyle(
                            fontSize: 15,
                            color: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.color,
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            onPressed: isSendEnabled
                                ? _sendVerificationCode
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isSendEnabled
                                  ? AppTheme.primary
                                  : disabledBg,
                              foregroundColor: isSendEnabled
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
                                    'Send Verification Code',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                      ] else ...[
                        const SizedBox(height: 4),
                        const Text(
                          'Enter Verification Code',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'We sent a code to your email. Please enter it below.',
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: 120,
                          child: TextField(
                            controller: _otpController,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            maxLength: 6,
                            style: const TextStyle(
                              fontSize: 18,
                              letterSpacing: 6,
                            ),
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
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            onPressed: isVerifyEnabled
                                ? _verifyAndCreateAccount
                                : null,
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
                        TextButton(
                          onPressed: _isLoading ? null : _resendCode,
                          child: const Text('Resend code'),
                        ),
                      ],
                      const Spacer(),
                      SizedBox(height: isWide ? 8 : 4),
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
