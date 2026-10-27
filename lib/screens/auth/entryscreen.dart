import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:talksy/main.dart';
import 'package:url_launcher/url_launcher.dart';

import 'create_account/createname.dart';
import 'login_account/login.dart';

// Defines the custom color palette for light and dark themes.
class AppTheme {
  static const primary = CupertinoColors.activeBlue;

  static const background = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFF6F8FA),
    darkColor: Color(0xFF0A0A0C),
  );

  static const backgroundEnd = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFEAEEF3),
    darkColor: Color(0xFF000000),
  );

  static const surface = CupertinoDynamicColor.withBrightness(
    color: CupertinoColors.white,
    darkColor: Color(0xFF161618),
  );

  static const button = CupertinoDynamicColor.withBrightness(
    color: CupertinoColors.white,
    darkColor: Color(0xFF1C1C1E),
  );

  static const border = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFE2E4E9),
    darkColor: Color(0xFF2C2C2E),
  );

  static const title = CupertinoColors.label;
  static const subtitle = CupertinoColors.secondaryLabel;
}

// Main screen widget managing the overall dynamic gradient layout.
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
              horizontal: MediaQuery.sizeOf(context).width * .075,
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Spacer(flex: 2),
                WelcomeCardHeader(),
                Spacer(flex: 3),
                ActionButtonsContainer(),
                Spacer(flex: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Displays the upper branding card with app icon, welcome title, and subtitle.
class WelcomeCardHeader extends StatelessWidget {
  const WelcomeCardHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 28),
      decoration: BoxDecoration(
        color: CupertinoDynamicColor.resolve(AppTheme.surface, context),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: CupertinoDynamicColor.resolve(AppTheme.border, context),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: CupertinoColors.black.withValues(alpha: dark ? 0.45 : 0.07),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              color: dark ? const Color(0xFF222225) : const Color(0xFFF0F3F7),
              border: Border.all(
                color: CupertinoDynamicColor.resolve(AppTheme.border, context),
                width: 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(21),
              child: Image.asset('assets/icon/icon.png', fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 26),
          Text(
            'Welcome Back',
            textAlign: TextAlign.center,
            style: AppTypography.welcomeTitle.copyWith(
              color: CupertinoDynamicColor.resolve(AppTheme.title, context),
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Sign in to continue your journey or create an account.',
            textAlign: TextAlign.center,
            style: AppTypography.welcomeSubtitle.copyWith(
              color: CupertinoDynamicColor.resolve(AppTheme.subtitle, context),
              fontSize: 14.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

// Groups authentication buttons and the authenticator download link vertically.
class ActionButtonsContainer extends StatelessWidget {
  const ActionButtonsContainer({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        PrimaryActionButton(),
        SizedBox(height: 16),
        SecondaryActionButton(),
        SizedBox(height: 14),
        AuthenticatorDownloadLink(),
      ],
    );
  }
}

// Renders the primary action button for user login.
class PrimaryActionButton extends StatelessWidget {
  const PrimaryActionButton({super.key});

  @override
  Widget build(BuildContext context) {
    return AppButton(
      text: 'Log In',
      icon: Icons.login_rounded,
      primary: true,
      onPressed: () => Navigator.push(
        context,
        CupertinoPageRoute(builder: (_) => const LoginScreen()),
      ),
    );
  }
}

// Renders the secondary action button for user account creation.
class SecondaryActionButton extends StatelessWidget {
  const SecondaryActionButton({super.key});

  @override
  Widget build(BuildContext context) {
    return AppButton(
      text: 'Create Account',
      icon: Icons.person_add_outlined,
      primary: false,
      onPressed: () => Navigator.push(
        context,
        CupertinoPageRoute(builder: (_) => const CreateNameScreen()),
      ),
    );
  }
}

// Displays a very small clickable link redirecting users to the Authenticator GitHub release.
class AuthenticatorDownloadLink extends StatefulWidget {
  const AuthenticatorDownloadLink({super.key});

  @override
  State<AuthenticatorDownloadLink> createState() =>
      _AuthenticatorDownloadLinkState();
}

// Manages the tap gesture state and browser launch operation for the download link.
class _AuthenticatorDownloadLinkState extends State<AuthenticatorDownloadLink> {
  late final TapGestureRecognizer _tapRecognizer;

  @override
  void initState() {
    super.initState();
    _tapRecognizer = TapGestureRecognizer()
      ..onTap = _launchAuthenticatorRelease;
  }

  @override
  void dispose() {
    _tapRecognizer.dispose();
    super.dispose();
  }

  // Launches the official release URL in an external browser app.
  Future<void> _launchAuthenticatorRelease() async {
    final Uri url = Uri.parse(
      'https://github.com/anjitchaudhary/talksy_authenticator/releases/tag/v0.1.0',
    );
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      // Handles potential url launch failures gracefully.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          style: TextStyle(
            fontSize: 11.0, // Made very-very small as requested
            color: CupertinoDynamicColor.resolve(AppTheme.subtitle, context),
          ),
          children: [
            TextSpan(
              text: 'Click here',
              style: TextStyle(
                color: CupertinoDynamicColor.resolve(AppTheme.primary, context),
                fontWeight: FontWeight.w600,
              ),
              recognizer: _tapRecognizer,
            ),
            const TextSpan(text: ' to download Authenticator app'),
          ],
        ),
      ),
    );
  }
}

// Custom reusable button widget supporting primary and outlined styles.
class AppButton extends StatelessWidget {
  final String text;
  final IconData icon;
  final bool primary;
  final VoidCallback onPressed;

  const AppButton({
    super.key,
    required this.text,
    required this.icon,
    required this.onPressed,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        pressedOpacity: 0.85,
        borderRadius: BorderRadius.circular(18),
        color: primary
            ? AppTheme.primary
            : CupertinoDynamicColor.resolve(AppTheme.button, context),
        onPressed: onPressed,
        child: Container(
          alignment: Alignment.center,
          decoration: primary
              ? BoxDecoration(borderRadius: BorderRadius.circular(18))
              : BoxDecoration(
                  border: Border.all(
                    color: CupertinoDynamicColor.resolve(
                      AppTheme.border,
                      context,
                    ),
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: primary
                    ? CupertinoColors.white
                    : CupertinoDynamicColor.resolve(AppTheme.title, context),
              ),
              const SizedBox(width: 10),
              Text(
                text,
                style: AppTypography.buttonLabel.copyWith(
                  color: primary
                      ? CupertinoColors.white
                      : CupertinoDynamicColor.resolve(AppTheme.title, context),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
