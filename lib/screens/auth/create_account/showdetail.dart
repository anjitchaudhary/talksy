import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:talksy/api_gateway.dart';
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
  final ApiGateway _api = ApiGateway.instance;

  bool _isLoading = false;
  bool _isDone = false;

  String get _email => widget.email.trim().toLowerCase();

  Future<String?> _uploadProfileImage() async {
    final file = widget.profileImage;
    if (file == null) return null;

    try {
      final bytes = await file.readAsBytes();
      return await _api.uploadImage(
        'data:image/jpeg;base64,${base64Encode(bytes)}',
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _verifyAndCreateAccount() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    var completed = false;

    try {
      if (await _api.isEmailRegistered(_email)) {
        _showSnack('This email is already registered. Please log in.');
        return;
      }

      final google = await _api.pickGoogleAccount();
      if (google == null) return;

      if (google.email.trim().toLowerCase() != _email) {
        _showSnack('Choose the Google account that uses $_email.');
        return;
      }

      try {
        await _api.createAccount(
          idToken: google.idToken,
          email: _email,
          password: widget.password,
          firstName: widget.firstName,
          lastName: widget.lastName,
          dob: widget.dob,
          gender: widget.gender,
        );
      } on GatewayException catch (e) {
        if (e.status != 409) rethrow;
      }

      final user = await _api.signIn(_email, widget.password);

      try {
        await _api.linkGoogle(google.idToken);
      } catch (_) {}

      final imageUrl = await _uploadProfileImage();
      if (imageUrl != null) await _api.saveAvatar(imageUrl);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('otp_verified_${user.id}', true);
      await SavedAccountStore.save(
        user: _api.currentUser ?? user,
        password: widget.password,
      );
      await _api.releaseGoogleAccount();

      completed = true;
      if (!mounted) return;
      setState(() => _isDone = true);
      await Future.delayed(const Duration(milliseconds: 700));

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        CupertinoPageRoute(
          builder: (_) => const HomeScreen(showSuccessPopup: true),
        ),
        (route) => false,
      );
    } on GatewayException catch (e) {
      _showSnack(_messageFor(e));
    } on TimeoutException {
      _showSnack('Connection timed out. Please check your internet.');
    } catch (_) {
      _showSnack('Something went wrong. Please try again.');
    } finally {
      if (!completed) {
        await _api.releaseGoogleAccount();
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  String _messageFor(GatewayException e) {
    switch (e.code) {
      case 'email_mismatch':
        return 'Choose the Google account that uses $_email.';
      case 'invalid_google_token':
        return 'Google verification failed. Please try again.';
      case 'email_exists':
      case 'signin_failed':
        return 'This email is already registered. Please log in.';
      case 'invalid_details':
        return 'Some of your details are invalid. Please go back and check.';
      default:
        return 'Could not create your account. Please try again.';
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _detailRow(IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Icon(icon, size: 28, color: Colors.grey),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
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

  Widget _profileCard(Color cardColor) {
    return Row(
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFC0C0C0), width: 1.5),
          ),
          child: CircleAvatar(
            radius: 28,
            backgroundColor: Colors.transparent,
            backgroundImage: widget.profileImage != null
                ? FileImage(widget.profileImage!)
                : null,
            child: widget.profileImage == null
                ? Icon(Icons.person, size: 25, color: Colors.grey.shade500)
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
                Text(widget.email, style: const TextStyle(color: Colors.grey)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buttonRow(Key key, Widget leading, String text) {
    return Row(
      key: key,
      mainAxisSize: MainAxisSize.min,
      children: [
        leading,
        const SizedBox(width: 12),
        Text(
          text,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buttonContent() {
    if (_isDone) {
      return _buttonRow(
        const ValueKey('done'),
        const Icon(Icons.check_circle_rounded, size: 24),
        'Verified',
      );
    }
    if (_isLoading) {
      return _buttonRow(
        const ValueKey('loading'),
        const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            color: Colors.white,
            strokeWidth: 2.5,
          ),
        ),
        'Verifying...',
      );
    }
    return _buttonRow(
      const ValueKey('idle'),
      const _GoogleMark(),
      'Verify with Google',
    );
  }

  Widget _verifyButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _verifyAndCreateAccount,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppTheme.primary,
          disabledForegroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(scale: animation, child: child),
          ),
          child: _buttonContent(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final background = Theme.of(context).scaffoldBackgroundColor;
    final cardColor = Theme.of(context).cardColor;

    return PopScope(
      canPop: !_isLoading,
      child: Scaffold(
        backgroundColor: background,
        appBar: AppBar(
          backgroundColor: background,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          elevation: 0,
          toolbarHeight: 40,
          leading: const BackButton(),
          titleSpacing: 0,
          title: const Text('Review & Verify'),
          actions: [
            IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: _isLoading ? null : _showDetailPopup,
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _profileCard(cardColor),
                const SizedBox(height: 30),
                Text(
                  'Verify your email with Google to complete your registration. '
                  'Choose the Google account that uses ${widget.email.trim()}.',
                  style: const TextStyle(fontSize: 15, height: 1.4),
                ),
                const SizedBox(height: 24),
                _verifyButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  static const _colors = [
    Color(0xFF4285F4),
    Color(0xFF34A853),
    Color(0xFFFBBC05),
    Color(0xFFEA4335),
    Color(0xFF4285F4),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) =>
            const SweepGradient(colors: _colors).createShader(bounds),
        child: const Text(
          'G',
          style: TextStyle(
            fontSize: 17,
            height: 1,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
