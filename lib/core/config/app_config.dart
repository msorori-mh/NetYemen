import 'package:flutter/foundation.dart';

class AppConfig {
  final String supabaseUrl;
  final String supabasePublishableKey;
  final String adminPasswordRecoveryRedirectUrl;

  const AppConfig({
    required this.supabaseUrl,
    required this.supabasePublishableKey,
    this.adminPasswordRecoveryRedirectUrl = '',
  });

  bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;

  bool get isDemoMode => !isConfigured && kDebugMode;

  bool get isReleaseUnconfigured => !isConfigured && kReleaseMode;

  static AppConfig fromEnvironment() {
    const url = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
    const key = String.fromEnvironment(
      'SUPABASE_PUBLISHABLE_KEY',
      defaultValue: '',
    );
    const recoveryRedirectUrl = String.fromEnvironment(
      'ADMIN_PASSWORD_RECOVERY_REDIRECT_URL',
      defaultValue: '',
    );
    return const AppConfig(
      supabaseUrl: url,
      supabasePublishableKey: key,
      adminPasswordRecoveryRedirectUrl: recoveryRedirectUrl,
    );
  }

  static const AppConfig demo = AppConfig(
    supabaseUrl: '',
    supabasePublishableKey: '',
  );

  Uri? get adminPasswordRecoveryRedirectUri {
    if (adminPasswordRecoveryRedirectUrl.isEmpty) return null;
    return Uri.tryParse(adminPasswordRecoveryRedirectUrl);
  }

  String? get adminPasswordRecoveryCallbackUrl {
    final uri = adminPasswordRecoveryRedirectUri;
    if (uri == null) return null;
    return uri.replace(queryParameters: {
      ...uri.queryParameters,
      'mode': 'recovery'
    }).toString();
  }

  bool get hasValidAdminPasswordRecoveryRedirectUrl {
    final uri = adminPasswordRecoveryRedirectUri;
    if (uri == null || !uri.hasAuthority) return false;
    if (uri.scheme == 'https') return true;
    return uri.scheme == 'http' &&
        (uri.host == 'localhost' || uri.host == '127.0.0.1');
  }

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
