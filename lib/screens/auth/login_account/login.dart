import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';

import 'home/home.dart';

class SavedAccount {
  final String displayName;
  final String email;
  final String? imagePath;
  SavedAccount({
    required this.displayName,
    required this.email,
    this.imagePath,
  });
  Map<String, dynamic> toJson() => {
    'displayName': displayName,
    'email': email,
    'imagePath': imagePath,
  };
  static SavedAccount fromJson(Map<String, dynamic> j) => SavedAccount(
    displayName: j['displayName'] as String,
    email: j['email'] as String,
    imagePath: j['imagePath'] as String?,
  );
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();
  final FlutterSecureStorage _secure = const FlutterSecureStorage();
  final ImagePicker _picker = ImagePicker();
  bool _remember = false;
  bool _isAuthenticating = false;
  bool _obscurePassword = true;
  List<SavedAccount> _savedAccounts = [];

  @override
  void initState() {
    super.initState();
    _loadSavedAccounts();
    _loadRememberedCredentials();
  }

  Future<void> _loadSavedAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('saved_accounts') ?? [];
    if (!mounted) return;
    setState(() {
      _savedAccounts = raw
          .map((s) {
            try {
              final m = jsonDecode(s) as Map<String, dynamic>;
              return SavedAccount.fromJson(m);
            } catch (_) {
              return SavedAccount(
                displayName: 'Unknown',
                email: '',
                imagePath: null,
              );
            }
          })
          .where((a) => a.email.isNotEmpty)
          .toList();
    });
  }

  Future<void> _loadRememberedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final rememberedEmail = prefs.getString('remembered_email');
    if (rememberedEmail != null) {
      final pwd = await _secure.read(key: 'pwd_$rememberedEmail');
      if (!mounted) return;
      if (pwd != null) {
        setState(() {
          _emailCtrl.text = rememberedEmail;
          _passCtrl.text = pwd;
          _remember = true;
        });
      }
    }
  }

  Future<void> _saveAccount(SavedAccount account, {String? password}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('saved_accounts') ?? [];
      final cleaned = <String>[];
      for (final s in list) {
        try {
          final m = jsonDecode(s) as Map<String, dynamic>;
          if (m['email'] != account.email) cleaned.add(s);
        } catch (_) {}
      }
      cleaned.insert(0, jsonEncode(account.toJson()));
      await prefs.setStringList('saved_accounts', cleaned);
      if (password != null) {
        await _secure.write(key: 'pwd_${account.email}', value: password);
        await prefs.setString('remembered_email', account.email);
      }
      await _loadSavedAccounts();
    } catch (_) {}
  }

  Future<void> _removeSavedAccount(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('saved_accounts') ?? [];
    final updated = <String>[];
    for (final s in list) {
      try {
        final m = jsonDecode(s) as Map<String, dynamic>;
        if (m['email'] != email) updated.add(s);
      } catch (_) {}
    }
    await prefs.setStringList('saved_accounts', updated);
    await _secure.delete(key: 'pwd_$email');
    final remembered = prefs.getString('remembered_email');
    if (remembered == email) await prefs.remove('remembered_email');
    await _loadSavedAccounts();
  }

  Future<void> _onAuthenticate() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    if (email.isEmpty || pass.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter email and password'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    setState(() => _isAuthenticating = true);
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    if (_remember) {
      try {
        await _saveAccount(
          SavedAccount(
            displayName: _displayNameFromEmail(email),
            email: email,
            imagePath: null,
          ),
          password: pass,
        );
      } catch (_) {}
    } else {
      try {
        final prefs = await SharedPreferences.getInstance();
        final remembered = prefs.getString('remembered_email');
        if (remembered == email) {
          await _secure.delete(key: 'pwd_$email');
          await prefs.remove('remembered_email');
        }
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() => _isAuthenticating = false);
    if (!mounted) return;
    Navigator.of(context)
        .pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
  }

  String _displayNameFromEmail(String email) {
    final name = email.split('@').first;
    final parts = name.split(RegExp(r'[._\-]'));
    final display = parts
        .map((p) => p.isEmpty ? '' : '${p[0].toUpperCase()}${p.substring(1)}')
        .join(' ');
    return display.isEmpty ? email : display;
  }

  Future<void> _pickProfileImageForAccount(SavedAccount account) async {
    final XFile? x = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 80,
    );
    if (x == null) return;
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('saved_accounts') ?? [];
    final updated = list.map((s) {
      try {
        final m = jsonDecode(s) as Map<String, dynamic>;
        if (m['email'] == account.email) {
          m['imagePath'] = x.path;
        }
        return jsonEncode(m);
      } catch (_) {
        return s;
      }
    }).toList();
    await prefs.setStringList('saved_accounts', updated);
    if (!mounted) return;
    await _loadSavedAccounts();
  }

  InputDecoration _inputDecoration({
    required String label,
    Widget? suffix,
    required BuildContext context,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final borderColor = isDark ? Colors.grey.shade700 : Colors.grey.shade300;
    final focusedColor = theme.colorScheme.primary;
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: theme.cardColor,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 14.0,
        vertical: 14.0,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: borderColor, width: 1.0),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: focusedColor, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.red.shade400, width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.red.shade600, width: 1.6),
      ),
      suffixIcon: suffix,
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    bool obscure = false,
    TextInputType keyboardType = TextInputType.text,
    Widget? suffix,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      decoration: _inputDecoration(
        label: label,
        suffix: suffix,
        context: context,
      ),
    );
  }

  Widget _buildSavedAccountsList({double avatarRadius = 32}) {
    if (_savedAccounts.isEmpty) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      height: 110,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _savedAccounts.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final acc = _savedAccounts[i];
          ImageProvider<Object>? avatarImage;
          if (acc.imagePath != null && acc.imagePath!.isNotEmpty) {
            if (acc.imagePath!.startsWith('http')) {
              avatarImage = NetworkImage(acc.imagePath!);
            } else {
              final f = File(acc.imagePath!);
              if (f.existsSync()) avatarImage = FileImage(f);
            }
          }
          final hasImage = avatarImage != null;
          return Container(
            width: 260,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () async {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const HomeScreen()),
                    );
                  },
                  onLongPress: () => _pickProfileImageForAccount(acc),
                  child: CircleAvatar(
                    radius: avatarRadius,
                    backgroundColor: Colors.grey.shade200,
                    backgroundImage: hasImage ? avatarImage : null,
                    child: !hasImage
                        ? Text(
                            acc.displayName.isNotEmpty
                                ? acc.displayName[0]
                                : '?',
                            style: const TextStyle(
                              fontSize: 20,
                              color: Colors.black54,
                            ),
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    acc.displayName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => _removeSavedAccount(acc.email),
                  child: const Text('Remove', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showSavedAccountsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final height = MediaQuery.of(context).size.height * 0.5;
        return SizedBox(
          height: height,
          child: Column(
            children: [
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Saved accounts',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSavedAccountsList(avatarRadius: 28),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final primary = Theme.of(context).colorScheme.primary;
    final isEnabled = !_isAuthenticating;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        toolbarHeight: 40,
        leading: const BackButton(),
        titleSpacing: 0,
        centerTitle: false,
        title: const Text(
          'Log In',
          textAlign: TextAlign.left,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'Saved users',
            onPressed: _showSavedAccountsSheet,
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 12,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 24,
                ),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      const Text(
                        'Welcome back',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Sign in with your email and password to continue.',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                      const SizedBox(height: 20),
                      _buildTextField(
                        label: 'Email',
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        label: 'Password',
                        controller: _passCtrl,
                        obscure: _obscurePassword,
                        suffix: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                            size: 20,
                          ),
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          splashRadius: 20,
                          tooltip: _obscurePassword
                              ? 'Show password'
                              : 'Hide password',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Transform.scale(
                            scale: 0.85,
                            child: Switch(
                              value: _remember,
                              onChanged: (v) => setState(() => _remember = v),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Remember password',
                              overflow: TextOverflow.visible,
                            ),
                          ),
                          const Spacer(),
                          const SizedBox(width: 8),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 45,
                        child: ElevatedButton(
                          onPressed: isEnabled ? _onAuthenticate : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isEnabled
                                ? primary
                                : Colors.grey.shade300,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: isEnabled ? 2 : 0,
                          ),
                          child: _isAuthenticating
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  'Authenticate',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: isEnabled
                                        ? Colors.white
                                        : Colors.grey.shade600,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 8,
                            ),
                            minimumSize: const Size(0, 0),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Password reset flow not implemented',
                                ),
                                backgroundColor: Colors.blueAccent,
                              ),
                            );
                          },
                          child: Text(
                            'Forgot password?',
                            style: TextStyle(color: primary),
                          ),
                        ),
                      ),
                      const Spacer(),
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
