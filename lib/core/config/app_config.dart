import 'package:flutter/foundation.dart';

class AppConfig {
  final String supabaseUrl;
  final String supabasePublishableKey;

  const AppConfig({
    required this.supabaseUrl,
    required this.supabasePublishableKey,
  });

  bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;

  bool get isDemoMode => !isConfigured && kDebugMode;

  bool get isReleaseUnconfigured =>
      !isConfigured && kReleaseMode;

  static AppConfig fromEnvironment() {
    const url = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
    const key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY', defaultValue: '');
    return AppConfig(supabaseUrl: url, supabasePublishableKey: key);
  }

  static const AppConfig demo = AppConfig(
    supabaseUrl: '',
    supabasePublishableKey: '',
  );

  Uri? get supabaseUri {
    if (!isConfigured) return null;
    return Uri.tryParse(supabaseUrl);
  }

  bool get hasValidSupabaseUrl {
    if (!isConfigured) return false;
    final uri = supabaseUri;
    return uri != null && (uri.scheme == 'https' || uri.scheme == 'http');
  }
}
