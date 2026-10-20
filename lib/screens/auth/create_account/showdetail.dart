import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talksy/screens/auth/entryscreen.dart';
import 'package:talksy/screens/auth/login_account/home/home.dart';
import 'package:talksy/screens/auth/login_account/login.dart'
    show SavedAccountStore;

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
  static String? _activeSessionEmail;

  final SupabaseClient _db = Supabase.instance.client;
  final TextEditingController _otpController = TextEditingController();

  bool _isOtpSent = false;
  bool _isLoading = false;
  DateTime? _otpExpiry;

  @override
  void initState() {
    super.initState();
    if (_activeSessionEmail == widget.email.trim()) {
      _isOtpSent = true;
      _checkExistingOtp();
    }
  }

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _checkExistingOtp() async {
    try {
      final res = await _db.rpc(
        'get_otp_status',
        params: {'p_email': widget.email.trim()},
      );
      if (res != null && res['exists'] == true && mounted) {
        setState(() {
          _otpExpiry = DateTime.parse(res['expires_at']).toLocal();
        });
      }
    } catch (_) {}
  }

  Future<String?> _uploadProfileImage() async {
    final file = widget.profileImage;
    if (file == null) return null;

    try {
      final bytes = await file.readAsBytes();
      final res = await _db.functions.invoke(
        'bright-function',
        body: {'image_base64': 'data:image/jpeg;base64,${base64Encode(bytes)}'},
      );
      final data = res.data;
      return data is Map ? data['url'] as String? : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _handleSendCode() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      await _db.functions.invoke('Otp', body: {'email': widget.email.trim()});

      _activeSessionEmail = widget.email.trim();
      if (!mounted) return;
      setState(() => _isOtpSent = true);
      _checkExistingOtp();
      _showSnack('Verification code sent successfully.');
    } on FunctionException catch (e) {
      _showSnack(
        e.status == 429
            ? 'Please wait a moment before requesting another code.'
            : 'Could not send the code. Please try again.',
      );
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
    if (_otpExpiry != null && DateTime.now().isAfter(_otpExpiry!)) {
      return _showSnack('Code has expired.');
    }

    setState(() => _isLoading = true);
    var otpUsed = false;

    try {
      final isValid = await _db.rpc(
        'verify_otp',
        params: {'p_email': widget.email.trim(), 'p_otp': token},
      );

      if (isValid != true) {
        _showSnack('Invalid verification code.');
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      _activeSessionEmail = null;
      otpUsed = true;

      final imageUrl = await _uploadProfileImage();
      final fullName = '${widget.firstName.trim()} ${widget.lastName.trim()}';

      final res = await _db.auth.signUp(
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

      final user = res.user;
      if (user == null) throw Exception('Signup failed');

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('otp_verified_${user.id}', true);
      await SavedAccountStore.save(user: user, password: widget.password);

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        CupertinoPageRoute(
          builder: (_) => const HomeScreen(showSuccessPopup: true),
        ),
        (route) => false,
      );
    } catch (_) {
      _showSnack('Error occurred during account creation.');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        if (otpUsed) _isOtpSent = false;
      });
      if (otpUsed) _otpController.clear();
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _detailRow(IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Icon(icon, size: 28, color: Colors.grey),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
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
        final textColor =
            Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black;

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
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 24),
              _detailRow(
                Icons.cake_outlined,
                'Date of Birth',
                DateFormat('MMMM dd, yyyy').format(widget.dob),
                textColor,
              ),
              const SizedBox(height: 20),
              _detailRow(
                Icons.person_outline,
                'Gender',
                widget.gender,
                textColor,
              ),
              const SizedBox(height: 20),
              _detailRow(
                Icons.lock_outline,
                'Password',
                '•' * widget.password.length,
                textColor,
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

    final isVerifyEnabled =
        !_isLoading && _otpController.text.trim().length == 6;

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
                      border: Border.all(
                        color: const Color(0xFFC0C0C0),
                        width: 1.5,
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 28,
                      backgroundColor: Colors.transparent,
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
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${widget.firstName} ${widget.lastName}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            widget.email,
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              if (!_isOtpSent) ...[
                const Text(
                  'Verify your email address to complete your registration.',
                  style: TextStyle(fontSize: 15),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleSendCode,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isLoading
                          ? disabledBg
                          : AppTheme.primary,
                      foregroundColor: Colors.white,
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
                        : const Text('Send Verification Code'),
                  ),
                ),
              ] else ...[
                const Text(
                  'Enter Verification Code',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
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
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
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
                      backgroundColor: isVerifyEnabled
                          ? AppTheme.primary
                          : disabledBg,
                      foregroundColor: Colors.white,
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
                        : const Text('Verify & Create Account'),
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
