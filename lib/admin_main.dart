import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/unconfigured_screen.dart';
import 'core/config/app_config.dart';
import 'core/config/app_environment.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/admin_auth_screen.dart';
import 'utils/constants.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final config = AppConfig.fromEnvironment();
  final environment = AppEnvironment.fromConfig(config);

  if (environment.state == AppBootstrapState.configured) {
    try {
      await Supabase.initialize(
        url: config.supabaseUrl,
        publishableKey: config.supabasePublishableKey,
      );
    } catch (_) {
      runApp(
        const ProviderScope(
          child: AdminConsoleApp(
            bootstrapError: 'تعذر تهيئة اتصال لوحة الإدارة.',
          ),
        ),
      );
      return;
    }
  }

  runApp(ProviderScope(child: AdminConsoleApp(environment: environment)));
}

class AdminConsoleApp extends StatelessWidget {
  final AppEnvironment? environment;
  final String? bootstrapError;

  const AdminConsoleApp({super.key, this.environment, this.bootstrapError});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '${AppConstants.appName} — الإدارة',
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.lightTheme,
      home: _home(),
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
    );
  }

  Widget _home() {
    if (bootstrapError != null) {
      return UnconfiguredScreen(message: bootstrapError!);
    }

    final state = environment?.state;
    if (state == AppBootstrapState.configured) {
      return const AdminAuthCoordinator();
    }

    return UnconfiguredScreen(
      message:
          environment?.errorMessage ??
          'لوحة الإدارة غير معدّة. يلزم إعداد اتصال Supabase.',
    );
  }
}
