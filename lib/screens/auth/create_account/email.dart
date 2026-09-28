import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:talksy/screens/auth/entryscreen.dart';

import 'createpassword.dart';

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

  bool _isButtonEnabled = false;

  @override
  void initState() {
    super.initState();
    _emailController.addListener(_validateEmail);
  }

  void _validateEmail() {
    final email = _emailController.text.trim();

    final isValid = RegExp(
      r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9-]+\.[a-zA-Z]+$",
    ).hasMatch(email);

    if (_isButtonEnabled != isValid) {
      setState(() {
        _isButtonEnabled = isValid;
      });
    }
  }

  void _onNextClicked() {
    if (!_isButtonEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid email address.'),
          backgroundColor: Colors.redAccent,
        ),
      );
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
    _emailController.removeListener(_validateEmail);
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
                'Enter the email address where you can be reached. It must be a working email.',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),

              const SizedBox(height: 20),

              DecoratedBox(
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    style: TextStyle(color: textColor),
                    decoration: const InputDecoration(
                      hintText: 'example@gmail.com',
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isButtonEnabled ? _onNextClicked : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isButtonEnabled
                        ? AppTheme.primary
                        : disabledBg,
                    foregroundColor: _isButtonEnabled
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
                  child: const Text(
                    'Next',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
