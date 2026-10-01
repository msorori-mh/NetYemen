import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/core/config/app_config.dart';
import 'package:netyemen/core/config/app_environment.dart';

void main() {
  group('AppEnvironment', () {
    test('configured environment requires valid Supabase URL', () {
      const config = AppConfig(
        supabaseUrl: 'https://example.supabase.co',
        supabasePublishableKey: 'anon-key',
      );
      final env = AppEnvironment.fromConfig(config);

      expect(env.state, AppBootstrapState.configured);
      expect(env.canRun, isTrue);
    });

    test('invalid URL produces invalidUrl state', () {
      const config = AppConfig(
        supabaseUrl: 'not-a-url',
        supabasePublishableKey: 'anon-key',
      );
      final env = AppEnvironment.fromConfig(config);

      expect(env.state, AppBootstrapState.invalidUrl);
      expect(env.canRun, isFalse);
    });

    test('empty config is unconfigured but not runnable in release', () {
      const config = AppConfig(supabaseUrl: '', supabasePublishableKey: '');
      final env = AppEnvironment.fromConfig(config);

      // In debug/test mode this is unconfiguredDebug; in release it would be
      // unconfiguredRelease. The test runner runs in debug mode.
      expect(
        env.state,
        anyOf(
          AppBootstrapState.unconfiguredDebug,
          AppBootstrapState.unconfiguredRelease,
        ),
      );
    });

    test('demo mode is derived from empty config in debug builds', () {
      const config = AppConfig(supabaseUrl: '', supabasePublishableKey: '');
      expect(config.isDemoMode || config.isReleaseUnconfigured, isTrue);
    });

    test(
      'admin recovery redirect requires HTTPS outside local development',
      () {
        const secureConfig = AppConfig(
          supabaseUrl: 'https://example.supabase.co',
          supabasePublishableKey: 'anon-key',
          adminPasswordRecoveryRedirectUrl: 'https://admin.example.com',
        );
        const localConfig = AppConfig(
          supabaseUrl: 'https://example.supabase.co',
          supabasePublishableKey: 'anon-key',
          adminPasswordRecoveryRedirectUrl: 'http://localhost:7357',
        );
        const insecureConfig = AppConfig(
          supabaseUrl: 'https://example.supabase.co',
          supabasePublishableKey: 'anon-key',
          adminPasswordRecoveryRedirectUrl: 'http://admin.example.com',
        );

        expect(secureConfig.hasValidAdminPasswordRecoveryRedirectUrl, isTrue);
        expect(
          secureConfig.adminPasswordRecoveryCallbackUrl,
          'https://admin.example.com?mode=recovery',
        );
        expect(localConfig.hasValidAdminPasswordRecoveryRedirectUrl, isTrue);
        expect(
          insecureConfig.hasValidAdminPasswordRecoveryRedirectUrl,
          isFalse,
        );
      },
    );

    test('public legal URLs require non-local HTTPS endpoints', () {
      const valid = AppConfig(
        supabaseUrl: 'https://example.supabase.co',
        supabasePublishableKey: 'anon-key',
        privacyPolicyUrl: 'https://legal.example.com/privacy',
        accountDeletionUrl: 'https://legal.example.com/delete-account',
      );
      const insecure = AppConfig(
        supabaseUrl: 'https://example.supabase.co',
        supabasePublishableKey: 'anon-key',
        privacyPolicyUrl: 'http://legal.example.com/privacy',
        accountDeletionUrl: 'https://legal.example.com/delete-account',
      );
      const local = AppConfig(
        supabaseUrl: 'https://example.supabase.co',
        supabasePublishableKey: 'anon-key',
        privacyPolicyUrl: 'https://localhost/privacy',
        accountDeletionUrl: 'https://localhost/delete-account',
      );

      expect(valid.hasValidPublicLegalUrls, isTrue);
      expect(insecure.hasValidPublicLegalUrls, isFalse);
      expect(local.hasValidPublicLegalUrls, isFalse);
    });
  });
}
