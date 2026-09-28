import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'screens/splashscreen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');

  await Supabase.initialize(
    url: dotenv.get('SUPABASE_URL'),
    publishableKey: dotenv.get('SUPABASE_PUBLISHABLE_KEY'),
  );

  runApp(const MyApp());
}

abstract final class AppTypography {
  static const String fontFamily = 'Roboto';
  static const List<String> fontFallback = <String>['Arial', 'sans-serif'];

  static const TextStyle defaultText = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
  );

  static const TextStyle welcomeTitle = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    decoration: TextDecoration.none,
  );

  static const TextStyle welcomeSubtitle = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.4,
    decoration: TextDecoration.none,
  );

  static const TextStyle splashCredit = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 17,
    decoration: TextDecoration.none,
  );

  static const TextStyle buttonLabel = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 16,
    fontWeight: FontWeight.w600,
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      builder: (context, child) {
        final isDark =
            MediaQuery.platformBrightnessOf(context) == Brightness.dark;

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: isDark
                ? Brightness.light
                : Brightness.dark,
            statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
          ),
          child: DefaultTextStyle.merge(
            style: AppTypography.defaultText,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      theme: ThemeData(
        brightness: Brightness.light,
        useMaterial3: true,
        fontFamily: AppTypography.fontFamily,
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: CupertinoPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          },
        ),
        splashColor: Colors.black.withValues(alpha: 0.18),
        highlightColor: Colors.black.withValues(alpha: 0.10),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
        ),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        fontFamily: AppTypography.fontFamily,
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: CupertinoPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          },
        ),
        splashColor: Colors.white.withValues(alpha: 0.22),
        highlightColor: Colors.white.withValues(alpha: 0.12),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      home: const SplashScreen(),
    );
  }
}
