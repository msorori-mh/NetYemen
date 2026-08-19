import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app_shell.dart';
import 'app/unconfigured_screen.dart';
import 'core/config/app_config.dart';
import 'core/config/app_environment.dart';
import 'core/theme/app_theme.dart';
import 'utils/constants.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();

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

class WaselNetApp extends StatelessWidget {
  final AppEnvironment environment;

  const WaselNetApp({super.key, required this.environment});

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
    switch (environment.state) {
      case AppBootstrapState.configured:
      case AppBootstrapState.unconfiguredDebug:
        return const AppShell();
      case AppBootstrapState.unconfiguredRelease:
        return UnconfiguredScreen(
          message:
              environment.errorMessage ??
              'التطبيق غير مُعدّ — يرجى إعادة التثبيت',
        );
      case AppBootstrapState.invalidUrl:
        return UnconfiguredScreen(
          message: environment.errorMessage ?? 'رابط Supabase غير صالح',
        );
      case AppBootstrapState.error:
        return UnconfiguredScreen(
          message: environment.errorMessage ?? 'حدث خطأ في بدء التطبيق',
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
