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
import 'app/demo_data_ribbon.dart';
import 'app/unconfigured_screen.dart';
import 'core/config/app_config.dart';
import 'core/config/app_constants.dart';
import 'core/config/app_environment.dart';
import 'core/error/error_log.dart';
import 'core/theme/app_theme.dart';
import 'features/security/data/pin_repository.dart';
import 'features/security/presentation/pin_gate.dart';
import 'features/security/presentation/sign_in_gate.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage _) async {
  try {
    await Firebase.initializeApp();
  } catch (error, stackTrace) {
    logError('Firebase background initialization failed', error, stackTrace);
  }
}

/// Routes uncaught framework and platform errors to the developer log so a
/// failure is diagnosable instead of silent. Nothing here reaches the user.
void _installErrorHandlers() {
  final presentFrameworkError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    logError('Uncaught Flutter framework error', details.exception,
        details.stack);
    presentFrameworkError?.call(details);
  };
  WidgetsBinding.instance.platformDispatcher.onError =
      (Object error, StackTrace stackTrace) {
    logError('Uncaught platform error', error, stackTrace);
    return true;
  };
}

/// Push is optional: when Firebase cannot start (missing or broken Google
/// services on the device) the app still runs and only push degrades.
Future<void> _initializeFirebase() async {
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (error, stackTrace) {
    logError('Firebase initialization failed; push is disabled', error,
        stackTrace);
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _installErrorHandlers();

  await _initializeFirebase();

  try {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  } catch (error, stackTrace) {
    logError('Could not lock the screen orientation', error, stackTrace);
  }

  final config = AppConfig.fromEnvironment();
  final environment = AppEnvironment.fromConfig(config);

  if (environment.state == AppBootstrapState.configured) {
    try {
      await Supabase.initialize(
        url: config.supabaseUrl,
        publishableKey: config.supabasePublishableKey,
      );
    } catch (error, stackTrace) {
      logError('Supabase initialization failed', error, stackTrace);
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
            home: const UnconfiguredScreen(
              message:
                  'تعذر تهيئة الاتصال بالخدمة. تحقق من اتصال الإنترنت ثم أعد فتح التطبيق.',
            ),
          ),
        ),
      );
      return;
    }
  }

  runApp(ProviderScope(child: WaselNetApp(environment: environment)));
}

class WaselNetApp extends ConsumerStatefulWidget {
  final AppEnvironment environment;

  const WaselNetApp({super.key, required this.environment});

  @override
  ConsumerState<WaselNetApp> createState() => _WaselNetAppState();
}

class _WaselNetAppState extends ConsumerState<WaselNetApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;
  StreamSubscription<AuthState>? _authSubscription;

  /// Supabase is only initialized for a configured build; nothing may touch
  /// `Supabase.instance` otherwise.
  bool get _hasBackend =>
      widget.environment.state == AppBootstrapState.configured;

  @override
  void initState() {
    super.initState();
    _listenForSignIn();
    _initDeepLinks();
  }

  /// Makes the PIN gate follow the auth state instead of individual screens.
  ///
  /// Any "signed in" event for an account that has not been gated yet sends
  /// the whole app through [PinGate] — this is what covers the Google OAuth
  /// return, which no screen is waiting for. Screens that route to the gate
  /// themselves claim their sign-in so the gate is not started twice.
  void _listenForSignIn() {
    if (!_hasBackend) return;
    final auth = Supabase.instance.client.auth;
    final tracker = SignedInGateTracker(initialUserId: auth.currentUser?.id);
    _authSubscription = auth.onAuthStateChange.listen(
      (authState) {
        if (authState.event == AuthChangeEvent.signedOut) {
          tracker.onSignedOut();
          // Covers every sign-out path (expired session, remote revocation),
          // not only the explicit button: the next sign-in must enter the PIN.
          unawaited(_forgetDeviceTrust());
          return;
        }
        if (authState.event != AuthChangeEvent.signedIn) return;
        if (!mounted) return;

        final mustGate = tracker.onSignedIn(
          authState.session?.user.id,
          claimedByScreen: ref.read(screenRoutedSignInProvider),
        );
        if (!mustGate) return;
        _navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const PinGate()),
          (_) => false,
        );
      },
      onError: (Object error, StackTrace stackTrace) {
        logError('Auth state stream error', error, stackTrace);
      },
    );
  }

  Future<void> _forgetDeviceTrust() async {
    try {
      await clearPinDeviceTrust();
    } catch (error, stackTrace) {
      logError('Could not clear PIN device trust', error, stackTrace);
    }
  }

  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();

    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        await _handleLink(initialUri);
      }
    } catch (error, stackTrace) {
      logError('Initial deep link unavailable', error, stackTrace);
    }

    if (!mounted) return;
    _linkSubscription = _appLinks.uriLinkStream.listen(
      (uri) => unawaited(_handleLink(uri)),
      onError: (Object error, StackTrace stackTrace) {
        logError('Deep link stream error', error, stackTrace);
      },
    );
  }

  Future<void> _handleLink(Uri uri) async {
    if (!_hasBackend) return;
    if (!uri.queryParameters.containsKey('code')) return;

    final auth = Supabase.instance.client.auth;
    if (auth.currentSession != null) return;

    try {
      await auth.getSessionFromUrl(uri);
    } on AuthException catch (error, stackTrace) {
      final message = error.message.toLowerCase();
      if (message.contains('code already used') ||
          message.contains('invalid') ||
          message.contains('pkce') ||
          message.contains('verifier')) {
        // Quietly ignore: supabase's internal listener might have won the race.
        return;
      }
      logError('OAuth code exchange failed', error, stackTrace);
      _showSignInError();
    } catch (error, stackTrace) {
      logError('OAuth code exchange failed', error, stackTrace);
      _showSignInError();
    }
  }

  void _showSignInError() {
    if (!mounted) return;
    _scaffoldMessengerKey.currentState?.showSnackBar(
      const SnackBar(
        content: Text('تعذر إكمال تسجيل الدخول. حاول مرة أخرى.'),
      ),
    );
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _scaffoldMessengerKey,
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
        final content = Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        );
        // Only a runnable app shows data; error screens need no demo mark.
        if (!widget.environment.canRun) return content;
        return DemoDataRibbon(child: content);
      },
    );
  }

  Widget _buildHome() {
    switch (widget.environment.state) {
      case AppBootstrapState.configured:
        return const PinGate();
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
