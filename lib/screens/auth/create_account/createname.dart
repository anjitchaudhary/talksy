import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:talksy/screens/auth/entryscreen.dart';

import 'dob.dart';

class CreateNameScreen extends StatefulWidget {
  const CreateNameScreen({super.key});

  @override
  State<CreateNameScreen> createState() => _CreateNameScreenState();
}

class _CreateNameScreenState extends State<CreateNameScreen> {
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  File? _profileImage;
  bool _isButtonEnabled = false;

  static const Color _silver = Color(0xFFC0C0C0);

  @override
  void initState() {
    super.initState();
    _firstNameController.addListener(_validateInput);
    _lastNameController.addListener(_validateInput);
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  void _validateInput() {
    final isNotEmpty =
        _firstNameController.text.trim().isNotEmpty &&
        _lastNameController.text.trim().isNotEmpty;
    if (_isButtonEnabled != isNotEmpty) {
      setState(() => _isButtonEnabled = isNotEmpty);
    }
  }

  Future<void> _pickImage() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 10,
      maxWidth: 400,
      maxHeight: 400,
    );
    if (image != null && mounted) {
      setState(() => _profileImage = File(image.path));
    }
  }

  void _onNextClicked() {
    if (!_isButtonEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter both First Name and Last Name'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    // Yaha keyboard lai unfocus (hide) garne code thapeko xu
    // Jasle garda screen transition ko bela UI jhayapa skip hudaina
    FocusScope.of(context).unfocus();

    // MaterialPageRoute use garda main.dart ko CupertinoPageTransitionsBuilder automatically apply hunxa
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DobScreen(
          firstName: _firstNameController.text.trim(),
          lastName: _lastNameController.text.trim(),
          profileImage: _profileImage,
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Theme.of(context).cardColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _silver, width: 1.2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _silver, width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _silver, width: 1.8),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final greyText = isDark ? Colors.grey.shade400 : Colors.grey;
    final disabledBg = isDark ? Colors.grey.shade700 : Colors.grey.shade300;
    final disabledFg = isDark ? Colors.grey.shade400 : Colors.grey.shade600;

    return Scaffold(
      backgroundColor: bg,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        toolbarHeight: 40,
        leading: const BackButton(),
        titleSpacing: 0,
        centerTitle: false,
        title: const Text('Create Name'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              const Text(
                "What's your name?",
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text(
                'Enter your real name and add a profile picture so friends can recognize you.',
                style: TextStyle(fontSize: 16, color: greyText),
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: _pickImage,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: _silver, width: 2),
                  ),
                  child: CircleAvatar(
                    radius: 48,
                    backgroundColor: isDark
                        ? Colors.grey.shade800
                        : Colors.grey.shade200,
                    backgroundImage: _profileImage != null
                        ? FileImage(_profileImage!)
                        : null,
                    child: _profileImage == null
                        ? Icon(
                            Icons.person,
                            size: 50,
                            color: Colors.grey.shade500,
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _pickImage,
                style: TextButton.styleFrom(
                  foregroundColor: isDark ? Colors.white : Colors.black87,
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Set Profile Photo',
                  style: TextStyle(fontSize: 15),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _firstNameController,
                textCapitalization: TextCapitalization.words,
                decoration: _inputDecoration('First Name'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _lastNameController,
                textCapitalization: TextCapitalization.words,
                decoration: _inputDecoration('Last Name'),
              ),
              const SizedBox(height: 30),
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
