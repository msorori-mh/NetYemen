import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app_shell.dart';
import 'app/unconfigured_screen.dart';
import 'core/config/app_config.dart';
import 'core/config/app_environment.dart';
import 'core/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

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
            locale: const Locale('ar'),
            supportedLocales: const [Locale('ar'), Locale('en')],
            home: UnconfiguredScreen(
              message: 'فشل تهيئة الاتصال: $e',
            ),
          ),
        ),
      );
      return;
    }
  }

  runApp(
    ProviderScope(
      overrides: [
        // Provide the parsed config so providers can use it
      ],
      child: NetYemenApp(environment: environment),
    ),
  );
}

class NetYemenApp extends StatelessWidget {
  final AppEnvironment environment;

  const NetYemenApp({super.key, required this.environment});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'NetYemen',
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      theme: AppTheme.lightTheme,
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    switch (environment.state) {
      case AppBootstrapState.configured:
      case AppBootstrapState.unconfiguredDebug:
        return const AppShell();
      case AppBootstrapState.unconfiguredRelease:
        return UnconfiguredScreen(
          message: environment.errorMessage ??
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
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
    }
  }
}
