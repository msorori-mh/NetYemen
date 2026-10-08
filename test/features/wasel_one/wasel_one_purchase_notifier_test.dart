import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/features/wasel_one/data/wasel_one_repository.dart';
import 'package:netyemen/features/wasel_one/domain/entities.dart';
import 'package:netyemen/features/wasel_one/presentation/wasel_one_providers.dart';

void main() {
  group('WaselOnePurchaseNotifier', () {
    test('reuses the same key after an ambiguous failure', () async {
      final repository = _RecordingRepository(failFirstAttempt: true);
      final container = _container(repository);
      addTearDown(container.dispose);
      await container.read(waselOnePurchaseProvider.future);

      final notifier = container.read(waselOnePurchaseProvider.notifier);
      await expectLater(notifier.purchase('plan-1'), throwsStateError);
      final result = await notifier.purchase('plan-1');

      expect(result.isCompleted, isTrue);
      expect(repository.idempotencyKeys, hasLength(2));
      expect(repository.idempotencyKeys[1], repository.idempotencyKeys[0]);
    });

    test('coalesces concurrent purchase taps for the same plan', () async {
      final gate = Completer<void>();
      final repository = _RecordingRepository(gate: gate);
      final container = _container(repository);
      addTearDown(container.dispose);
      await container.read(waselOnePurchaseProvider.future);

      final notifier = container.read(waselOnePurchaseProvider.notifier);
      final first = notifier.purchase('plan-1');
      final second = notifier.purchase('plan-1');
      gate.complete();

      final results = await Future.wait([first, second]);
      expect(results[0].purchaseId, results[1].purchaseId);
      expect(repository.idempotencyKeys, hasLength(1));
    });

    test('mints a new key after a confirmed purchase', () async {
      final repository = _RecordingRepository();
      final container = _container(repository);
      addTearDown(container.dispose);
      await container.read(waselOnePurchaseProvider.future);

      final notifier = container.read(waselOnePurchaseProvider.notifier);
      await notifier.purchase('plan-1');
      await notifier.purchase('plan-1');

      expect(repository.idempotencyKeys, hasLength(2));
      expect(
          repository.idempotencyKeys[1], isNot(repository.idempotencyKeys[0]));
    });
  });

  group('WaselOneCredentialNotifier', () {
    test('a double tap issues a single credential', () async {
      final gate = Completer<void>();
      final repository = _RecordingRepository(gate: gate);
      final container = _container(repository);
      addTearDown(container.dispose);
      await container.read(waselOneCredentialProvider.future);

      final notifier = container.read(waselOneCredentialProvider.notifier);
      final first = notifier.issue('entitlement-1');
      final second = notifier.issue('entitlement-1');
      gate.complete();

      final results = await Future.wait([first, second]);
      expect(results[0].credentialId, results[1].credentialId);
      expect(
        repository.issuedFor,
        ['entitlement-1'],
        reason: 'issuing again would invalidate the credential on screen',
      );
    });

    test('the issue slot is exclusive until it is released', () async {
      final container = _container(_RecordingRepository());
      addTearDown(container.dispose);
      await container.read(waselOneCredentialProvider.future);

      final notifier = container.read(waselOneCredentialProvider.notifier);
      expect(notifier.tryBegin(), isTrue);
      expect(notifier.tryBegin(), isFalse);

      notifier.finish();
      expect(container.read(waselOneCredentialProvider).value, isNull);
      expect(notifier.tryBegin(), isTrue);
    });
  });
}

ProviderContainer _container(WaselOneRepository repository) {
  return ProviderContainer(
    overrides: [waselOneRepositoryProvider.overrideWithValue(repository)],
  );
}

class _RecordingRepository implements WaselOneRepository {
  final bool failFirstAttempt;
  final Completer<void>? gate;
  final List<String> idempotencyKeys = [];

  _RecordingRepository({this.failFirstAttempt = false, this.gate});

  @override
  Future<WaselOnePurchaseResult> purchasePlan({
    required String planId,
    required String idempotencyKey,
  }) async {
    idempotencyKeys.add(idempotencyKey);
    if (failFirstAttempt && idempotencyKeys.length == 1) {
      throw StateError('CONNECTION_LOST_AFTER_SEND');
    }
    await gate?.future;
    return const WaselOnePurchaseResult(
      purchaseId: 'purchase-1',
      entitlementId: 'entitlement-1',
      status: 'completed',
      amountPaid: 1000,
      currency: 'YER',
      newBalance: 4000,
      replayed: false,
    );
  }

  @override
  Future<List<FederatedAccessPlan>> getPublicPlans() async => const [];

  @override
  Future<List<AccessEntitlement>> getMyEntitlements() async => const [];

  final List<String> issuedFor = [];

  @override
  Future<RadiusAccessCredential> issueAccessCredential(
    String entitlementId,
  ) async {
    issuedFor.add(entitlementId);
    await gate?.future;
    return RadiusAccessCredential(
      credentialId: 'credential-${issuedFor.length}',
      username: 'w1-test',
      password: 'TEST-ONLY',
      expiresAt: DateTime.utc(2030),
    );
  }
}
