import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/core/utils/uuid_generator.dart';
import 'package:netyemen/features/network_requests/data/fake_network_request_repository.dart';
import 'package:netyemen/features/network_requests/presentation/network_request_providers.dart';

void main() {
  group('SubmitRequestNotifier', () {
    final uuidPattern = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );

    ProviderContainer createContainer() {
      return ProviderContainer(
        overrides: [
          networkRequestRepositoryProvider.overrideWithValue(
            FakeNetworkRequestRepository(),
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

      final key = container.read(pendingIdempotencyKeyProvider);
      expect(key, isNull,
          reason: 'key should be cleared after a successful submission');
    });

    test('submit uses the same idempotency key on retry', () async {
      final container = createContainer();
      final notifier = container.read(submitRequestNotifierProvider);
      final repo = container.read(networkRequestRepositoryProvider)
          as FakeNetworkRequestRepository;

      // First attempt fails, so the key must be retained for a retry.
      repo.shouldThrow = true;
      await expectLater(
        () => notifier.submit(observedSsidDisplay: 'HomeWiFi'),
        throwsException,
      );

      final firstKey = container.read(pendingIdempotencyKeyProvider);
      expect(firstKey, isNotNull);
      expect(uuidPattern.hasMatch(firstKey!), isTrue);

      repo.shouldThrow = false;
      final result = await notifier.submit(observedSsidDisplay: 'HomeWiFi');

      final secondKey = container.read(pendingIdempotencyKeyProvider);
      expect(secondKey, isNull,
          reason: 'key should be cleared after success');
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

    test('retry with the same key returns the same request', () async {
      final container = createContainer();
      final notifier = container.read(submitRequestNotifierProvider);
      final repo = container.read(networkRequestRepositoryProvider)
          as FakeNetworkRequestRepository;

      final idempotencyKey = UuidGenerator.generateV4();
      container.read(pendingIdempotencyKeyProvider.notifier).state =
          idempotencyKey;

      final first = await notifier.submit(observedSsidDisplay: 'SameSSID');
      expect(repo.requests.length, 1);

      // The key is cleared on success; simulate a retry by restoring it.
      container.read(pendingIdempotencyKeyProvider.notifier).state =
          idempotencyKey;
      final retry = await notifier.submit(observedSsidDisplay: 'Different');

      expect(retry.id, first.id,
          reason: 'retry with the same key must return the existing request');
      expect(repo.requests.length, 1);
    });
  });
}
