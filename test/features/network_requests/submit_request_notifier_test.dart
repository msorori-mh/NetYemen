import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/core/config/app_config.dart';
import 'package:netyemen/core/utils/uuid_generator.dart';
import 'package:netyemen/features/network_requests/data/fake_network_request_repository.dart';
import 'package:netyemen/features/network_requests/presentation/network_request_providers.dart';
import 'package:netyemen/providers/app_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('SubmitRequestNotifier', () {
    final uuidPattern = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );

    final testUser = User(
      id: 'a1a1a1a1-a1a1-4a1a-a1a1-a1a1a1a1a1a1',
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: DateTime.now().toIso8601String(),
    );

    ProviderContainer createContainer() {
      return ProviderContainer(
        overrides: [
          networkRequestRepositoryProvider.overrideWithValue(
            FakeNetworkRequestRepository(),
          ),
          currentUserProvider.overrideWithValue(testUser),
          appConfigProvider.overrideWithValue(
            const AppConfig(
              supabaseUrl: 'http://127.0.0.1:54321',
              supabasePublishableKey: 'test-publishable-key',
            ),
          ),
        ],
      );
    }

    test('submit generates a valid UUID v4 idempotency key', () async {
      final container = createContainer();
      final notifier = container.read(submitRequestNotifierProvider);

      await notifier.submit(observedSsidDisplay: 'HomeWiFi');

      final state = container.read(submitRequestStateProvider);
      expect(state, isA<AsyncData>());

      final session = container.read(pendingIdempotencySessionProvider);
      expect(session, isNull,
          reason: 'session should be cleared after a successful submission');
    });

    test('submit uses the same idempotency key on retry', () async {
      final container = createContainer();
      final notifier = container.read(submitRequestNotifierProvider);
      final repo = container.read(networkRequestRepositoryProvider)
          as FakeNetworkRequestRepository;

      // First attempt fails, so the session must be retained for a retry.
      repo.shouldThrow = true;
      await expectLater(
        () => notifier.submit(observedSsidDisplay: 'HomeWiFi'),
        throwsException,
      );

      final firstSession = container.read(pendingIdempotencySessionProvider);
      expect(firstSession, isNotNull);
      expect(uuidPattern.hasMatch(firstSession!.key), isTrue);

      repo.shouldThrow = false;
      final result = await notifier.submit(observedSsidDisplay: 'HomeWiFi');

      final secondSession = container.read(pendingIdempotencySessionProvider);
      expect(secondSession, isNull,
          reason: 'session should be cleared after success');
      expect(result.observedSsidDisplay, 'HomeWiFi');
    });

    test('independent submissions receive distinct idempotency keys', () async {
      final container = createContainer();
      final notifier = container.read(submitRequestNotifierProvider);
      final repo = container.read(networkRequestRepositoryProvider)
          as FakeNetworkRequestRepository;

      final capturedKeys = <String>{};
      for (var i = 0; i < 5; i++) {
        await notifier.submit(observedSsidDisplay: 'Network $i');
        capturedKeys.addAll(repo.idempotencyKeys);
      }

      expect(capturedKeys.length, 5);
    });

    test('retry after failure with the same payload returns the same request',
        () async {
      final container = createContainer();
      final notifier = container.read(submitRequestNotifierProvider);
      final repo = container.read(networkRequestRepositoryProvider)
          as FakeNetworkRequestRepository;

      repo.shouldThrow = true;
      await expectLater(
        () => notifier.submit(observedSsidDisplay: 'SameSSID'),
        throwsException,
      );

      final failedSession = container.read(pendingIdempotencySessionProvider);
      expect(failedSession, isNotNull);

      repo.shouldThrow = false;
      final result = await notifier.submit(observedSsidDisplay: 'SameSSID');

      expect(result.observedSsidDisplay, 'SameSSID');
      expect(repo.requests.length, 1,
          reason: 'retry after failure must not create a duplicate request');
    });

    test('changed payload after failure mints a new idempotency key', () async {
      final container = createContainer();
      final notifier = container.read(submitRequestNotifierProvider);
      final repo = container.read(networkRequestRepositoryProvider)
          as FakeNetworkRequestRepository;

      repo.shouldThrow = true;
      await expectLater(
        () => notifier.submit(observedSsidDisplay: 'OriginalSSID'),
        throwsException,
      );

      final failedSession = container.read(pendingIdempotencySessionProvider);
      expect(failedSession, isNotNull);
      final failedKey = failedSession!.key;

      repo.shouldThrow = false;
      await notifier.submit(observedSsidDisplay: 'ChangedSSID');

      final newSession = container.read(pendingIdempotencySessionProvider);
      expect(newSession, isNull);
      expect(repo.requests.length, 1);
      expect(repo.idempotencyKeys.single, isNot(failedKey),
          reason: 'a changed logical request must use a new idempotency key');
    });

    test('resetIdempotency discards a pending session', () {
      final container = createContainer();
      final notifier = container.read(submitRequestNotifierProvider);

      final idempotencyKey = UuidGenerator.generateV4();
      container.read(pendingIdempotencySessionProvider.notifier).state =
          IdempotencySession(idempotencyKey, 'stale-fingerprint');

      notifier.resetIdempotency();

      expect(container.read(pendingIdempotencySessionProvider), isNull);
      expect(container.read(submitRequestStateProvider), isNull);
    });
  });
}
