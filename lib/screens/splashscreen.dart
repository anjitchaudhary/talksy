import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:talksy/main.dart';

import 'auth/entryscreen.dart';
import 'auth/login_account/home/home.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  Timer? _navigationTimer;
  late final AnimationController _dotsController;

  @override
  void initState() {
    super.initState();

    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();

    _checkSessionAndNavigate();
  }

  Future<void> _checkSessionAndNavigate() async {
    _navigationTimer = Timer(const Duration(milliseconds: 1500), () async {
      if (!mounted) return;

      final session = Supabase.instance.client.auth.currentSession;
      final prefs = await SharedPreferences.getInstance();
      bool isVerified = false;

      if (session != null) {
        isVerified = prefs.getBool('otp_verified_${session.user.id}') ?? false;
        if (!isVerified) {
          await Supabase.instance.client.auth.signOut();
        }
      }

      if (!mounted) return;

      final targetScreen = (session != null && isVerified)
          ? const HomeScreen(showSuccessPopup: false)
          : const EntryScreen();

      Navigator.pushReplacement(
        context,
        CupertinoPageRoute(builder: (_) => targetScreen),
      );
    });
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    _dotsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;
    final dotColor = isDark
        ? CupertinoColors.white
        : const Color.fromARGB(255, 53, 53, 53);

    return CupertinoPageScaffold(
      child: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset('assets/icon/icon.png', width: size.width * 0.20),
                  const SizedBox(height: 10),
                  AnimatedBuilder(
                    animation: _dotsController,
                    builder: (context, child) {
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(4, (index) {
                          final delay = index * 0.15;
                          final raw = (_dotsController.value - delay) % 1.0;
                          final value = raw < 0 ? raw + 1.0 : raw;

                          double opacity;
                          if (value < 0.4) {
                            opacity = Curves.easeOut.transform(value / 0.4);
                          } else if (value < 0.7) {
                            opacity = 1.0;
                          } else {
                            opacity =
                                1.0 -
                                Curves.easeIn.transform((value - 0.7) / 0.3);
                          }

                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            child: Opacity(
                              opacity: opacity.clamp(0.25, 1.0),
                              child: Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: dotColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          );
                        }),
                      );
                    },
                  ),
                ],
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.only(bottom: size.height * 0.05),
                child: Text(
                  'By\nNexusWeave',
                  textAlign: TextAlign.center,
                  style: AppTypography.splashCredit.copyWith(
                    color: isDark
                        ? CupertinoColors.white
                        : CupertinoColors.black,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
