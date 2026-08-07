import 'package:flutter/foundation.dart';
import 'app_config.dart';

enum AppBootstrapState {
  configuring,
  configured,
  unconfiguredDebug,
  unconfiguredRelease,
  invalidUrl,
  error,
}

class AppEnvironment {
  final AppConfig config;
  final AppBootstrapState state;
  final String? errorMessage;

  const AppEnvironment({
    required this.config,
    required this.state,
    this.errorMessage,
  });

  factory AppEnvironment.fromConfig(AppConfig config) {
    if (config.isConfigured) {
      if (!config.hasValidSupabaseUrl) {
        return AppEnvironment(
          config: config,
          state: AppBootstrapState.invalidUrl,
          errorMessage: 'رابط Supabase غير صالح',
        );
      }
      return const AppEnvironment(
        config: AppConfig(supabaseUrl: '', supabasePublishableKey: ''),
        state: AppBootstrapState.configured,
      ).copyWith(config: config);
    }

    if (kReleaseMode) {
      return AppEnvironment(
        config: config,
        state: AppBootstrapState.unconfiguredRelease,
        errorMessage: 'التطبيق غير مُعدّ — يرجى إعادة التثبيت',
      );
    }

    return AppEnvironment(
      config: config,
      state: AppBootstrapState.unconfiguredDebug,
    );
  }

  AppEnvironment copyWith({
    AppConfig? config,
    AppBootstrapState? state,
    String? errorMessage,
  }) {
    return AppEnvironment(
      config: config ?? this.config,
      state: state ?? this.state,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  bool get canRun =>
      state == AppBootstrapState.configured ||
      state == AppBootstrapState.unconfiguredDebug;
}
