import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'api_gateway.dart';
import 'screens/splashscreen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');

  await Supabase.initialize(
    url: dotenv.get('SUPABASE_URL'),
    publishableKey: dotenv.get('SUPABASE_PUBLISHABLE_KEY'),
  );

  await GoogleSignIn.instance.initialize(
    serverClientId: dotenv.maybeGet('GOOGLE_WEB_CLIENT_ID'),
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

class PresenceService {
  PresenceService._();

  static final PresenceService instance = PresenceService._();

  final ApiGateway _db = ApiGateway.instance;

  final ValueNotifier<Set<String>> onlineIds = ValueNotifier<Set<String>>({});
  final ValueNotifier<bool> connected = ValueNotifier<bool>(true);

  RealtimeChannel? _presenceCh;
  RealtimeChannel? _inboxCh;
  Timer? _beat;
  String? _uid;
  bool _joined = false;

  void start() {
    final user = _db.currentUser;
    if (user == null || _uid == user.id) return;
    if (_uid != null) unawaited(stop());

    _uid = user.id;
    _joinPresence();
    _listenInbox();
    _beat = Timer.periodic(const Duration(seconds: 20), (_) => _ping());
    _ping();
  }

  Future<void> stop() async {
    if (_uid == null) return;

    final channels = [_presenceCh, _inboxCh];
    _beat?.cancel();
    _beat = null;
    _presenceCh = null;
    _inboxCh = null;
    _uid = null;
    _joined = false;
    onlineIds.value = {};

    try {
      await _db.rpc('touch_last_seen');
    } catch (_) {}

    for (final ch in channels) {
      if (ch != null) await _db.removeChannel(ch);
    }
  }

  void _joinPresence() {
    final ch = _db.channel(
      'online_users',
      opts: RealtimeChannelConfig(key: _uid!),
    );
    _presenceCh = ch;

    ch.onPresenceSync((_) => _syncOnline()).subscribe((status, [error]) async {
      if (_presenceCh != ch) return;

      if (status == RealtimeSubscribeStatus.subscribed) {
        _joined = true;
        connected.value = true;
        await ch.track({
          'user_id': _uid,
          'online_at': DateTime.now().toUtc().toIso8601String(),
        });
      } else {
        _joined = false;
        connected.value = false;
      }
    });
  }

  void _syncOnline() {
    final ch = _presenceCh;
    if (ch == null) return;

    final ids = <String>{};
    for (final state in ch.presenceState()) {
      for (final p in state.presences) {
        final id = p.payload['user_id'];
        if (id is String) ids.add(id);
      }
    }
    onlineIds.value = ids;
  }

  void _listenInbox() {
    _inboxCh = _db
        .channel('inbox_$_uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'receiver_id',
            value: _uid!,
          ),
          callback: (_) => _markDelivered(),
        )
        .subscribe();
  }

  Future<void> _markDelivered() async {
    try {
      await _db.rpc('mark_delivered');
    } catch (_) {}
  }

  Future<void> _ping() async {
    if (_uid == null) return;

    try {
      await _db.rpc('touch_last_seen');
      connected.value = true;
      await _markDelivered();
      if (!_joined) await _rejoin();
    } catch (_) {
      connected.value = false;
    }
  }

  Future<void> _rejoin() async {
    final old = _presenceCh;
    _presenceCh = null;
    if (old != null) await _db.removeChannel(old);
    if (_uid != null) _joinPresence();
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PresenceService.instance.start();
    _authSub = ApiGateway.instance.authChanges.listen((data) {
      if (data.session != null) {
        PresenceService.instance.start();
      } else {
        PresenceService.instance.stop();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      PresenceService.instance.start();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      PresenceService.instance.stop();
    }
  }

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
