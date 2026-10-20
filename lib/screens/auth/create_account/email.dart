import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  final SupabaseClient _supabase = Supabase.instance.client;

  Timer? _debounce;
  bool _isChecking = false;
  bool _isEmailAvailable = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _emailController.addListener(_onEmailChanged);
  }

  void _onEmailChanged() {
    final email = _emailController.text.trim();

    // Reset debounce timer on every keystroke to prevent spamming Supabase requests
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    // Check email regex format strictly ending with .com
    final isValidFormat = RegExp(
      r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9-]+\.com$",
      caseSensitive: false,
    ).hasMatch(email);

    if (email.isEmpty) {
      setState(() {
        _isChecking = false;
        _isEmailAvailable = false;
        _errorMessage = null;
      });
      return;
    }

    if (!isValidFormat) {
      setState(() {
        _isChecking = false;
        _isEmailAvailable = false;
        _errorMessage = 'Please enter a valid email ending with .com';
      });
      return;
    }

    // Set checking state to true while debouncing
    setState(() {
      _isChecking = true;
      _errorMessage = null;
      _isEmailAvailable = false;
    });

    // Wait 500ms after typing stops before querying Supabase
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _checkEmailExistenceInSupabase(email);
    });
  }

  Future<void> _checkEmailExistenceInSupabase(String email) async {
    try {
      bool emailExists = false;
      bool checkSuccessful = false;

      // 1. Try calling the Supabase RPC function first (Best way)
      try {
        final rpcRes = await _supabase.rpc(
          'check_email_exists',
          params: {'email_input': email},
        );
        if (rpcRes is bool) {
          emailExists = rpcRes;
          checkSuccessful = true;
        }
      } catch (rpcError) {
        debugPrint('RPC Error (Did you create the SQL function?): $rpcError');

        // 2. Fallback to 'profiles' table if RPC fails
        try {
          final profileRes = await _supabase
              .from('profiles')
              .select('id')
              .eq('email', email)
              .maybeSingle();

          emailExists = profileRes != null;
          checkSuccessful = true;
        } catch (tableError) {
          debugPrint(
            'Table Error (RLS blocking or table missing): $tableError',
          );
        }
      }

      if (!mounted) return;

      if (!checkSuccessful) {
        setState(() {
          _isChecking = false;
          _isEmailAvailable = false;
          _errorMessage = 'Database setup incomplete. Check console logs.';
        });
        return;
      }

      if (emailExists) {
        setState(() {
          _isChecking = false;
          _isEmailAvailable = false;
          _errorMessage = 'This email is already taken, try another';
        });
      } else {
        setState(() {
          _isChecking = false;
          _isEmailAvailable = true;
          _errorMessage = null;
        });
      }
    } catch (e) {
      debugPrint('Unexpected connection error: $e');
      if (!mounted) return;
      setState(() {
        _isChecking = false;
        _isEmailAvailable = false;
        _errorMessage = 'Could not verify email. Check your connection.';
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
    _debounce?.cancel();
    _emailController.removeListener(_onEmailChanged);
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
                          style: TextStyle(color: textColor),
                          decoration: const InputDecoration(
                            hintText: 'example@gmail.com',
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      if (_isChecking)
                        const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else if (_isEmailAvailable)
                        const Icon(
                          Icons.check_circle,
                          color: Colors.green,
                          size: 20,
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
