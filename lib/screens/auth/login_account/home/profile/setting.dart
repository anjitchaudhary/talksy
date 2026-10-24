import '../../login.dart';
import 'archived.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SettingScreen extends StatelessWidget {
  const SettingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : Colors.white;
    final dividerColor = isDark
        ? const Color(0xFF2C2C2E)
        : const Color(0xFFE5E5EA);
    final sectionHeaderColor = isDark
        ? const Color(0xFF8E8E93)
        : const Color(0xFF6D6D72);
    final cardColor = isDark
        ? const Color(0xFF1C1C1E)
        : const Color(0xFFF9F9F9);
    final textColor = isDark ? Colors.white : Colors.black87;
    final iconColor = isDark
        ? const Color(0xFF8E8E93)
        : const Color(0xFF555555);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(40),
        child: AppBar(
          backgroundColor: bgColor,
          elevation: 0,
          automaticallyImplyLeading: false,
          titleSpacing: 0,
          title: SafeArea(
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(32, 32),
                    onPressed: () => Navigator.pop(context),
                    child: Icon(
                      Icons.arrow_back_ios_new,
                      size: 20,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Settings',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 12, bottom: 8),
                child: Text(
                  'Account',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: sectionHeaderColor,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF2C2C2E)
                        : const Color(0xFFE5E5EA),
                    width: 0.5,
                  ),
                ),
                child: Column(
                  children: [
                    _buildSettingItem(
                      icon: Icons.person_outline,
                      title: 'Account information',
                      textColor: textColor,
                      iconColor: iconColor,
                      onTap: () {},
                    ),
                    Divider(
                      height: 0.5,
                      thickness: 0.5,
                      color: dividerColor,
                      indent: 52,
                    ),
                    _buildSettingItem(
                      icon: Icons.edit_outlined,
                      title: 'Change name',
                      textColor: textColor,
                      iconColor: iconColor,
                      onTap: () {},
                    ),
                    Divider(
                      height: 0.5,
                      thickness: 0.5,
                      color: dividerColor,
                      indent: 52,
                    ),
                    _buildSettingItem(
                      icon: Icons.lock_outline,
                      title: 'Change password',
                      textColor: textColor,
                      iconColor: iconColor,
                      onTap: () {},
                    ),
                    Divider(
                      height: 0.5,
                      thickness: 0.5,
                      color: dividerColor,
                      indent: 52,
                    ),
                    _buildSettingItem(
                      icon: Icons.verified_outlined,
                      title: 'Blue tick badge',
                      textColor: textColor,
                      iconColor: iconColor,
                      onTap: () {},
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.only(left: 12, bottom: 8),
                child: Text(
                  'Message',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: sectionHeaderColor,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF2C2C2E)
                        : const Color(0xFFE5E5EA),
                    width: 0.5,
                  ),
                ),
                child: Column(
                  children: [
                    _buildSettingItem(
                      icon: Icons.archive_outlined,
                      title: 'Archived',
                      textColor: textColor,
                      iconColor: iconColor,
                      onTap: () => Navigator.push(
                        context,
                        CupertinoPageRoute(
                          builder: (_) => const ArchivedScreen(),
                        ),
                      ),
                    ),
                    Divider(
                      height: 0.5,
                      thickness: 0.5,
                      color: dividerColor,
                      indent: 52,
                    ),
                    _buildSettingItem(
                      icon: Icons.message_outlined,
                      title: 'Message popup',
                      textColor: textColor,
                      iconColor: iconColor,
                      onTap: () {},
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Container(
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF2C2C2E)
                        : const Color(0xFFE5E5EA),
                    width: 0.5,
                  ),
                ),
                child: _buildSettingItem(
                  icon: Icons.logout,
                  title: 'Account logout',
                  textColor: Colors.redAccent,
                  iconColor: Colors.redAccent,
                  onTap: () {
                    showCupertinoDialog(
                      context: context,
                      builder: (dialogContext) => CupertinoAlertDialog(
                        title: const Text('Log out'),
                        content: const Text(
                          'Are you sure to log out this account?',
                        ),
                        actions: [
                          CupertinoDialogAction(
                            isDefaultAction: true,
                            onPressed: () => Navigator.pop(dialogContext),
                            child: const Text('Cancel'),
                          ),
                          CupertinoDialogAction(
                            isDestructiveAction: true,
                            onPressed: () async {
                              Navigator.pop(dialogContext);
                              showCupertinoDialog(
                                context: context,
                                barrierDismissible: false,
                                builder: (loadingContext) =>
                                    const CupertinoAlertDialog(
                                      content: Padding(
                                        padding: EdgeInsets.all(12),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            CupertinoActivityIndicator(),
                                            SizedBox(width: 12),
                                            Text('Logging out...'),
                                          ],
                                        ),
                                      ),
                                    ),
                              );
                              await Supabase.instance.client.auth.signOut();
                              if (!context.mounted) return;
                              Navigator.of(context).pushAndRemoveUntil(
                                CupertinoPageRoute(
                                  builder: (_) => const LoginScreen(),
                                ),
                                (route) => false,
                              );
                            },
                            child: const Text('Yes'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingItem({
    required IconData icon,
    required String title,
    required Color textColor,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: iconColor),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                  color: textColor,
                ),
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 14,
              color: iconColor.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    );
  }
}
