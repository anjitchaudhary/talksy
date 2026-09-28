import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:talksy/screens/auth/entryscreen.dart';

import 'email.dart';

class GenderScreen extends StatefulWidget {
  final String firstName;
  final String lastName;
  final File? profileImage;
  final DateTime dob;

  const GenderScreen({
    super.key,
    required this.firstName,
    required this.lastName,
    this.profileImage,
    required this.dob,
  });

  static Route route({
    required String firstName,
    required String lastName,
    File? profileImage,
    required DateTime dob,
  }) {
    return CupertinoPageRoute(
      builder: (_) => GenderScreen(
        firstName: firstName,
        lastName: lastName,
        profileImage: profileImage,
        dob: dob,
      ),
    );
  }

  @override
  State<GenderScreen> createState() => _GenderScreenState();
}

class _GenderScreenState extends State<GenderScreen> {
  String? _selectedGender;

  void _onNextClicked() {
    if (_selectedGender == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a gender to continue.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => EmailScreen(
          firstName: widget.firstName,
          lastName: widget.lastName,
          profileImage: widget.profileImage,
          dob: widget.dob,
          gender: _selectedGender!,
        ),
      ),
    );
  }

  Widget _buildGenderOption(String gender) {
    final isSelected = _selectedGender == gender;
    final cardColor = Theme.of(context).cardColor;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedGender = gender;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? CupertinoColors.activeBlue
                : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              gender,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            isSelected
                ? const Icon(
                    Icons.check_circle,
                    color: CupertinoColors.activeBlue,
                  )
                : Icon(Icons.circle_outlined, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = Theme.of(context).scaffoldBackgroundColor;
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
        title: const Text('Select Gender'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              const Text(
                "What's your gender?",
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                'You can change who sees your gender on your profile later.',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              _buildGenderOption('Male'),
              const SizedBox(height: 12),
              _buildGenderOption('Female'),
              const SizedBox(height: 12),
              _buildGenderOption('Others'),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _selectedGender != null ? _onNextClicked : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _selectedGender != null
                        ? AppTheme.primary
                        : disabledBg,
                    foregroundColor: _selectedGender != null
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
