import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/core/config/app_config.dart';
import 'package:netyemen/features/network_requests/presentation/network_request_providers.dart';
import 'package:netyemen/providers/app_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('MyRequestsNotifier', () {
    ProviderContainer createContainer({
      required AppConfig config,
      required User? user,
    }) {
      return ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(config),
          currentUserProvider.overrideWithValue(user),
        ],
      );
    }

    test('returns empty list when configured but no user is signed in', () async {
      final container = createContainer(
        config: const AppConfig(
          supabaseUrl: 'http://127.0.0.1:54321',
          supabasePublishableKey: 'test',
        ),
        user: null,
      );

      final requests = await container.read(myRequestsProvider.future);
      expect(requests, isEmpty);
    });

    test('fetches requests in demo mode even without a user', () async {
      final container = createContainer(
        config: AppConfig.demo,
        user: null,
      );

      final requests = await container.read(myRequestsProvider.future);
      expect(requests, isEmpty);
    });
  });
}
