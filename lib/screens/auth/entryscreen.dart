import 'package:flutter/cupertino.dart';
import 'package:talksy/main.dart';

import 'create_account/createname.dart';
import 'login_account/login.dart';

class AppTheme {
  static const primary = CupertinoColors.activeBlue;

  static const background = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFFDFDFD),
    darkColor: Color(0xFF1C1C1E),
  );

  static const backgroundEnd = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFF0F4F8),
    darkColor: Color(0xFF000000),
  );

  static const button = CupertinoDynamicColor.withBrightness(
    color: CupertinoColors.white,
    darkColor: Color(0xFF2C2C2E),
  );

  static const border = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFD1D1D6),
    darkColor: Color(0xFF5A5A60),
  );

  static const title = CupertinoColors.label;
  static const subtitle = CupertinoColors.secondaryLabel;

  static const silverBorder = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFC0C0C0),
    darkColor: Color(0xFFA8A8AE),
  );
}

class EntryScreen extends StatelessWidget {
  const EntryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            CupertinoDynamicColor.resolve(AppTheme.background, context),
            CupertinoDynamicColor.resolve(AppTheme.backgroundEnd, context),
          ],
        ),
      ),
      child: CupertinoPageScaffold(
        backgroundColor: const Color(0x00000000),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: MediaQuery.sizeOf(context).width * .08,
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Spacer(flex: 3),
                WelcomeHeader(),
                Spacer(flex: 4),
                ActionButtons(),
                Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class WelcomeHeader extends StatelessWidget {
  const WelcomeHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: CupertinoDynamicColor.resolve(
              AppTheme.primary,
              context,
            ).withValues(alpha: 0.1),
            shape: BoxShape.circle,
            border: Border.all(
              color: CupertinoDynamicColor.resolve(
                AppTheme.silverBorder,
                context,
              ),
              width: 1.8,
            ),
          ),
          child: Image.asset(
            'assets/icon/icon.png',
            width: 64,
            height: 64,
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(height: 32),
        Text(
          'Welcome Back',
          textAlign: TextAlign.center,
          style: AppTypography.welcomeTitle.copyWith(
            color: CupertinoDynamicColor.resolve(AppTheme.title, context),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Sign in to continue your journey or create a new account to get started.',
          textAlign: TextAlign.center,
          style: AppTypography.welcomeSubtitle.copyWith(
            color: CupertinoDynamicColor.resolve(AppTheme.subtitle, context),
          ),
        ),
      ],
    );
  }
}

class ActionButtons extends StatelessWidget {
  const ActionButtons({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AppButton(
          text: 'Log In',
          primary: true,
          onPressed: () => Navigator.push(
            context,
            CupertinoPageRoute(builder: (_) => const LoginScreen()),
          ),
        ),
        const SizedBox(height: 14),
        AppButton(
          text: 'Create Account',
          onPressed: () => Navigator.push(
            context,
            CupertinoPageRoute(builder: (_) => const CreateNameScreen()),
          ),
        ),
      ],
    );
  }
}

class AppButton extends StatelessWidget {
  final String text;
  final bool primary;
  final VoidCallback onPressed;

  const AppButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    final dark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        pressedOpacity: 0.7,
        borderRadius: BorderRadius.circular(16),
        color: primary
            ? AppTheme.primary
            : CupertinoDynamicColor.resolve(AppTheme.button, context),
        onPressed: onPressed,
        child: Container(
          alignment: Alignment.center,
          decoration: primary
              ? null
              : BoxDecoration(
                  border: Border.all(
                    color: dark
                        ? const Color(0xFF5A5A60)
                        : const Color(0xFFD1D1D6),
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
          child: Text(
            text,
            style: AppTypography.buttonLabel.copyWith(
              color: primary
                  ? CupertinoColors.white
                  : CupertinoDynamicColor.resolve(AppTheme.title, context),
            ),
          ),
        ),
      ),
    );
  }
}
