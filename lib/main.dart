import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app_links/app_links.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app_shell.dart';
import 'app/unconfigured_screen.dart';
import 'core/config/app_config.dart';
import 'core/config/app_constants.dart';
import 'core/config/app_environment.dart';
import 'core/theme/app_theme.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage _) async {
  await Firebase.initializeApp();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final config = AppConfig.fromEnvironment();
  final environment = AppEnvironment.fromConfig(config);

  if (environment.state == AppBootstrapState.configured) {
    try {
      await Supabase.initialize(
        url: config.supabaseUrl,
        publishableKey: config.supabasePublishableKey,
      );
    } catch (e) {
      runApp(
        ProviderScope(
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            title: AppConstants.appName,
            locale: const Locale('ar'),
            supportedLocales: const [Locale('ar'), Locale('en')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            localeResolutionCallback: _resolveLocale,
            home: UnconfiguredScreen(message: 'فشل تهيئة الاتصال: $e'),
          ),
        ),
      );
      return;
    }
  }

  runApp(ProviderScope(child: WaselNetApp(environment: environment)));
}

class WaselNetApp extends StatefulWidget {
  final AppEnvironment environment;

  const WaselNetApp({super.key, required this.environment});

  @override
  State<WaselNetApp> createState() => _WaselNetAppState();
}

class _WaselNetAppState extends State<WaselNetApp> {
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
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
            if (mounted) {
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                SnackBar(content: Text('خطأ في المصادقة: ${e.message}')),
              );
            }
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              const SnackBar(
                  content: Text('حدث خطأ غير متوقع أثناء تسجيل الدخول')),
            );
          }
        }
      }
    }
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: AppConstants.appName,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      localeResolutionCallback: _resolveLocale,
      theme: AppTheme.lightTheme,
      home: _buildHome(),
      builder: (context, child) {
        return Directionality(textDirection: TextDirection.rtl, child: child!);
      },
    );
  }

  Widget _buildHome() {
    switch (widget.environment.state) {
      case AppBootstrapState.configured:
      case AppBootstrapState.unconfiguredDebug:
        return const AppShell();
      case AppBootstrapState.unconfiguredRelease:
        return UnconfiguredScreen(
          message: widget.environment.errorMessage ??
              'التطبيق غير مُعدّ — يرجى إعادة التثبيت',
        );
      case AppBootstrapState.invalidUrl:
        return UnconfiguredScreen(
          message: widget.environment.errorMessage ?? 'رابط Supabase غير صالح',
        );
      case AppBootstrapState.error:
        return UnconfiguredScreen(
          message: widget.environment.errorMessage ?? 'حدث خطأ في بدء التطبيق',
        );
      case AppBootstrapState.configuring:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
  }
}

/// Fallback to Arabic for any unsupported device locale, preserving the
/// Arabic-first UX while keeping English available in supportedLocales.
Locale? _resolveLocale(Locale? locale, Iterable<Locale> supportedLocales) {
  if (locale == null) return const Locale('ar');
  for (final supported in supportedLocales) {
    if (supported.languageCode == locale.languageCode) {
      return supported;
    }
  }
  return const Locale('ar');
}
