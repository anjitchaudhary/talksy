import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:talksy/api_gateway.dart';
import 'package:talksy/screens/auth/entryscreen.dart';

import 'createpassword.dart';

final RegExp _emailPattern = RegExp(
  r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$",
);

class EmailScreen extends StatefulWidget {
  final String firstName;
  final String lastName;
  final File? profileImage;
  final DateTime dob;
  final String gender;

  const EmailScreen({
    super.key,
    required this.firstName,
    required this.lastName,
    this.profileImage,
    required this.dob,
    required this.gender,
  });

  static Route route({
    required String firstName,
    required String lastName,
    File? profileImage,
    required DateTime dob,
    required String gender,
  }) {
    return CupertinoPageRoute(
      builder: (_) => EmailScreen(
        firstName: firstName,
        lastName: lastName,
        profileImage: profileImage,
        dob: dob,
        gender: gender,
      ),
    );
  }

  @override
  State<EmailScreen> createState() => _EmailScreenState();
}

class _EmailScreenState extends State<EmailScreen> {
  final TextEditingController _emailController = TextEditingController();

  int _requestId = 0;
  bool _isChecking = false;
  bool _isEmailAvailable = false;
  String? _errorMessage;

  void _onEmailChanged(String _) {
    _requestId++;
    setState(() {
      _isChecking = false;
      _isEmailAvailable = false;
      _errorMessage = null;
    });
  }

  Future<void> _checkEmail() async {
    final email = _emailController.text.trim();
    if (_isChecking || email.isEmpty) return;

    if (email.length > 254 || !_emailPattern.hasMatch(email)) {
      setState(() => _errorMessage = 'Please enter a valid email address');
      return;
    }

    final requestId = ++_requestId;
    setState(() {
      _isChecking = true;
      _isEmailAvailable = false;
      _errorMessage = null;
    });

    try {
      final exists = await ApiGateway.instance.emailExists(email);
      if (!mounted || requestId != _requestId) return;

      setState(() {
        _isChecking = false;
        _isEmailAvailable = !exists;
        _errorMessage = exists
            ? 'This email is already taken, try another'
            : null;
      });
    } catch (e) {
      debugPrint('Email check failed: $e');
      if (!mounted || requestId != _requestId) return;

      final rateLimited = e is GatewayException && e.code == 'rate_limited';
      setState(() {
        _isChecking = false;
        _isEmailAvailable = false;
        _errorMessage = rateLimited
            ? 'Too many attempts. Please wait a minute and try again.'
            : 'Could not verify email. Check your connection.';
      });
    }
  }

  void _onNextClicked() {
    if (!_isEmailAvailable || _isChecking) {
      if (_errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_errorMessage!),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => CreatePasswordScreen(
          firstName: widget.firstName,
          lastName: widget.lastName,
          profileImage: widget.profileImage,
          dob: widget.dob,
          gender: widget.gender,
          email: _emailController.text.trim(),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = Theme.of(context).scaffoldBackgroundColor;
    final cardColor = Theme.of(context).cardColor;
    final textColor = Theme.of(context).textTheme.bodyLarge?.color;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final disabledBg = isDark ? Colors.grey.shade700 : Colors.grey.shade300;
    final disabledFg = isDark ? Colors.grey.shade400 : Colors.grey.shade600;

    final bool isButtonEnabled = _isEmailAvailable && !_isChecking;

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
        title: const Text('Set Email'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),

              const Text(
                "What's your email?",
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 10),

              const Text(
                'Enter the email address where you can be reached. It must be a working email. Once you use this email, you can\'t change it later.',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),

              const SizedBox(height: 20),

              DecoratedBox(
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _errorMessage != null
                        ? Colors.redAccent
                        : (_isEmailAvailable
                              ? Colors.green
                              : Colors.grey.shade300),
                    width: _errorMessage != null || _isEmailAvailable ? 1.5 : 1,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.search,
                          onChanged: _onEmailChanged,
                          onSubmitted: (_) => _checkEmail(),
                          style: TextStyle(color: textColor),
                          decoration: const InputDecoration(
                            hintText: 'example@gmail.com',
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      if (_isChecking)
                        const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.primary,
                          ),
                        )
                      else if (_isEmailAvailable)
                        const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(
                            Icons.check_circle_rounded,
                            color: Colors.green,
                            size: 20,
                          ),
                        )
                      else
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _checkEmail,
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.search_rounded,
                                color: AppTheme.primary,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: isButtonEnabled ? _onNextClicked : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isButtonEnabled
                        ? AppTheme.primary
                        : disabledBg,
                    foregroundColor: isButtonEnabled
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
                  child: _isChecking
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Next',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
