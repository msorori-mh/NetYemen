import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_links/app_links.dart';

import 'utils/constants.dart';
import 'utils/app_theme.dart';
import 'screens/splash_screen.dart';
import 'screens/pin_entry_screen.dart';

final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    publishableKey: AppConstants.supabaseAnonKey,
  );

  runApp(const ProviderScope(child: NetYemenOwnerApp()));
}

class NetYemenOwnerApp extends StatefulWidget {
  const NetYemenOwnerApp({super.key});

  @override
  State<NetYemenOwnerApp> createState() => _NetYemenOwnerAppState();
}

class _NetYemenOwnerAppState extends State<NetYemenOwnerApp> with WidgetsBindingObserver {
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;
  DateTime? _lastActiveTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initDeepLinks();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _linkSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_lastActiveTime != null) {
        final diff = DateTime.now().difference(_lastActiveTime!);
        if (diff.inMinutes >= 15) {
          final session = Supabase.instance.client.auth.currentSession;
          if (session != null) {
            navigatorKey.currentState?.push(
              MaterialPageRoute(builder: (_) => const PinEntryScreen(isAutoLock: true)),
            );
          }
        }
      }
      _lastActiveTime = null;
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _lastActiveTime ??= DateTime.now();
    }
  }

  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();

    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleLink(initialUri);
      }
    } catch (e) {
      // Ignore
    }

    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      _handleLink(uri);
    }, onError: (err) {
      // Ignore
    });
  }

  Future<void> _handleLink(Uri uri) async {
    if (uri.queryParameters.containsKey('code')) {
      if (Supabase.instance.client.auth.currentSession == null) {
        try {
          await Supabase.instance.client.auth.getSessionFromUrl(uri);
        } on AuthException catch (e) {
          if (e.message.toLowerCase().contains('code already used') || 
              e.message.toLowerCase().contains('invalid') || 
              e.message.toLowerCase().contains('pkce') ||
              e.message.toLowerCase().contains('verifier')) {
            // Quietly ignore: supabase's internal listener might have won the race.
          } else {
            scaffoldMessengerKey.currentState?.showSnackBar(
              SnackBar(content: Text('خطأ المصادقة: ${e.message}')),
            );
          }
        } catch (e) {
          scaffoldMessengerKey.currentState?.showSnackBar(
            const SnackBar(content: Text('حدث خطأ أثناء معالجة الرابط')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: scaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      title: AppConstants.appName,
      locale: const Locale('ar', 'YE'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ar', 'YE'),
        Locale('en', 'US'),
      ],
      theme: AppTheme.themeData,
      home: const SplashScreen(),
    );
  }
}
