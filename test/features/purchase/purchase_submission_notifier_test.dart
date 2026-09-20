import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/features/purchase/data/fake_purchase_repository.dart';
import 'package:netyemen/features/purchase/data/purchase_repository.dart';
import 'package:netyemen/features/purchase/domain/entities.dart';
import 'package:netyemen/features/purchase/presentation/purchase_providers.dart';

void main() {
  group('PurchaseSubmissionNotifier', () {
    test('reuses the same idempotency key after an ambiguous failure',
        () async {
      final repository = _RecordingPurchaseRepository(failFirstAttempt: true);
      final container = _container(repository);
      addTearDown(container.dispose);
      await container.read(purchaseSubmissionProvider.future);

      final notifier = container.read(purchaseSubmissionProvider.notifier);
      await expectLater(
        notifier.submit('package-1'),
        throwsA(isA<StateError>()),
      );
      final result = await notifier.submit('package-1');

      expect(result['purchase_id'], 'purchase-1');
      expect(repository.idempotencyKeys, hasLength(2));
      expect(
        repository.idempotencyKeys[1],
        repository.idempotencyKeys[0],
        reason: 'a retry must replay the original logical purchase',
      );
    });

    test('coalesces concurrent submits for the same package', () async {
      final gate = Completer<void>();
      final repository = _RecordingPurchaseRepository(gate: gate);
      final container = _container(repository);
      addTearDown(container.dispose);
      await container.read(purchaseSubmissionProvider.future);

      final notifier = container.read(purchaseSubmissionProvider.notifier);
      final first = notifier.submit('package-1');
      final second = notifier.submit('package-1');
      gate.complete();

      final results = await Future.wait([first, second]);

      expect(results[0], results[1]);
      expect(repository.idempotencyKeys, hasLength(1));
    });

    test('mints a new key after a confirmed successful purchase', () async {
      final repository = _RecordingPurchaseRepository();
      final container = _container(repository);
      addTearDown(container.dispose);
      await container.read(purchaseSubmissionProvider.future);

      final notifier = container.read(purchaseSubmissionProvider.notifier);
      await notifier.submit('package-1');
      await notifier.submit('package-1');

      expect(repository.idempotencyKeys, hasLength(2));
      expect(
        repository.idempotencyKeys[1],
        isNot(repository.idempotencyKeys[0]),
        reason: 'a confirmed purchase closes its idempotency session',
      );
    });
  });

  test('fake repository replays a key without creating a second order',
      () async {
    final repository = FakePurchaseRepository();

    final first = await repository.purchasePackage(
      packageId: 'package-1',
      idempotencyKey: 'key-1',
    );
    final replay = await repository.purchasePackage(
      packageId: 'package-1',
      idempotencyKey: 'key-1',
    );

    expect(replay['purchase_id'], first['purchase_id']);
    expect(replay['replayed'], isTrue);
    expect(repository.orders, hasLength(1));
  });
}

ProviderContainer _container(PurchaseRepository repository) {
  return ProviderContainer(
    overrides: [
      purchaseRepositoryProvider.overrideWithValue(repository),
    ],
  );
}

class _RecordingPurchaseRepository implements PurchaseRepository {
  final bool failFirstAttempt;
  final Completer<void>? gate;
  final List<String> idempotencyKeys = [];

  _RecordingPurchaseRepository({
    this.failFirstAttempt = false,
    this.gate,
  });

  @override
  Future<Map<String, dynamic>> purchasePackage({
    required String packageId,
    required String idempotencyKey,
  }) async {
    idempotencyKeys.add(idempotencyKey);
    if (failFirstAttempt && idempotencyKeys.length == 1) {
      throw StateError('CONNECTION_LOST_AFTER_SEND');
    }
    await gate?.future;
    return {
      'purchase_id': 'purchase-1',
      'package_id': packageId,
      'status': 'completed',
    };
  }

  @override
  Future<List<PurchaseOrder>> getMyPurchaseOrders() async => const [];

  @override
  Future<List<FulfillmentRecord>> getMyFulfillmentRecords() async => const [];

  @override
  Future<CardRevealResult> revealPurchaseCardSecret(String purchaseId) {
    throw UnimplementedError();
  }

  @override
  Future<void> submitInvalidCardDispute(String purchaseId, String reason) {
    throw UnimplementedError();
  }
}
