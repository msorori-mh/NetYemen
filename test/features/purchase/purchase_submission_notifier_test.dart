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
        notifier.submit('package-1', expectedPrice: 1000),
        throwsA(isA<StateError>()),
      );
      final result = await notifier.submit('package-1', expectedPrice: 1000);

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
      final first = notifier.submit('package-1', expectedPrice: 1000);
      final second = notifier.submit('package-1', expectedPrice: 1000);
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
      await notifier.submit('package-1', expectedPrice: 1000);
      await notifier.submit('package-1', expectedPrice: 1000);

      expect(repository.idempotencyKeys, hasLength(2));
      expect(
        repository.idempotencyKeys[1],
        isNot(repository.idempotencyKeys[0]),
        reason: 'a confirmed purchase closes its idempotency session',
      );
    });

    test('sends the confirmed price as the expected price', () async {
      final repository = _RecordingPurchaseRepository();
      final container = _container(repository);
      addTearDown(container.dispose);
      await container.read(purchaseSubmissionProvider.future);

      await container
          .read(purchaseSubmissionProvider.notifier)
          .submit('package-1', expectedPrice: 2500);

      expect(repository.expectedPrices, [2500]);
    });

    test('a changed confirmed price starts a new logical purchase', () async {
      final repository = _RecordingPurchaseRepository(failFirstAttempt: true);
      final container = _container(repository);
      addTearDown(container.dispose);
      await container.read(purchaseSubmissionProvider.future);

      final notifier = container.read(purchaseSubmissionProvider.notifier);
      await expectLater(
        notifier.submit('package-1', expectedPrice: 1000),
        throwsA(isA<StateError>()),
      );
      await notifier.submit('package-1', expectedPrice: 1200);

      expect(repository.expectedPrices, [1000, 1200]);
      expect(
        repository.idempotencyKeys[1],
        isNot(repository.idempotencyKeys[0]),
        reason: 'a different price is a different purchase, not a replay',
      );
    });

    test('PRICE_CHANGED is explained and closes the session', () async {
      final repository = _RecordingPurchaseRepository(currentPrice: 1500);
      final container = _container(repository);
      addTearDown(container.dispose);
      await container.read(purchaseSubmissionProvider.future);

      final notifier = container.read(purchaseSubmissionProvider.notifier);
      await expectLater(
        notifier.submit('package-1', expectedPrice: 1000),
        throwsA(isA<StateError>()),
      );

      final state = container.read(purchaseSubmissionProvider);
      expect(state.hasError, isTrue);
      expect(isPriceChangedError(state.error!), isTrue);
      expect(purchaseErrorMessage(state.error!), contains('تغيّر سعر'));

      repository.currentPrice = 1000;
      await notifier.submit('package-1', expectedPrice: 1000);
      expect(
        repository.idempotencyKeys[1],
        isNot(repository.idempotencyKeys[0]),
        reason: 'a refused price never debited, so nothing is replayed',
      );
    });

    test('a failed purchase does not describe another package', () async {
      final repository = _RecordingPurchaseRepository(failFirstAttempt: true);
      final container = _container(repository);
      addTearDown(container.dispose);
      await container.read(purchaseSubmissionProvider.future);

      final notifier = container.read(purchaseSubmissionProvider.notifier);
      await expectLater(
        notifier.submit('package-a', expectedPrice: 1000),
        throwsA(isA<StateError>()),
      );

      expect(container.read(purchaseSubmissionProvider).hasError, isTrue);
      expect(
        notifier.describes(packageId: 'package-a', expectedPrice: 1000),
        isTrue,
      );
      expect(
        notifier.describes(packageId: 'package-b', expectedPrice: 1000),
        isFalse,
        reason: 'package B must not inherit the error of package A',
      );

      notifier.reset();
      expect(container.read(purchaseSubmissionProvider).hasError, isFalse);
      expect(
        notifier.describes(packageId: 'package-a', expectedPrice: 1000),
        isFalse,
      );
    });

    test('maps server refusals to specific messages', () {
      expect(
        purchaseErrorMessage(StateError('WALLET_FROZEN')),
        contains('موقوفة'),
      );
      expect(
        purchaseErrorMessage(StateError('INSUFFICIENT_BALANCE')),
        contains('غير كافٍ'),
      );
      expect(
        purchaseErrorMessage(StateError('INACTIVE_PROFILE: not active')),
        contains('غير مفعّل'),
      );
      expect(
        purchaseErrorMessage(StateError('IDEMPOTENCY_KEY_REUSED: other')),
        contains('لم يُخصم'),
      );
    });

    test('a key the server refused as reused is never sent again', () async {
      final repository = _RecordingPurchaseRepository(keyReusedOnce: true);
      final container = _container(repository);
      addTearDown(container.dispose);
      await container.read(purchaseSubmissionProvider.future);

      final notifier = container.read(purchaseSubmissionProvider.notifier);
      await expectLater(
        notifier.submit('package-1', expectedPrice: 1000),
        throwsA(isA<StateError>()),
      );
      await notifier.submit('package-1', expectedPrice: 1000);

      expect(repository.idempotencyKeys, hasLength(2));
      expect(
        repository.idempotencyKeys[1],
        isNot(repository.idempotencyKeys[0]),
      );
    });
  });

  test('fake repository replays a key without creating a second order',
      () async {
    final repository = FakePurchaseRepository();

    final first = await repository.purchasePackage(
      packageId: 'package-1',
      idempotencyKey: 'key-1',
      expectedPrice: 1000,
    );
    final replay = await repository.purchasePackage(
      packageId: 'package-1',
      idempotencyKey: 'key-1',
      expectedPrice: 1000,
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
  final List<int> expectedPrices = [];

  /// When set, mirrors the server refusing a stale confirmed price.
  int? currentPrice;

  /// When true, the first attempt is refused with `IDEMPOTENCY_KEY_REUSED`.
  final bool keyReusedOnce;

  _RecordingPurchaseRepository({
    this.failFirstAttempt = false,
    this.gate,
    this.currentPrice,
    this.keyReusedOnce = false,
  });

  @override
  Future<Map<String, dynamic>> purchasePackage({
    required String packageId,
    required String idempotencyKey,
    required int expectedPrice,
  }) async {
    idempotencyKeys.add(idempotencyKey);
    expectedPrices.add(expectedPrice);
    if (failFirstAttempt && idempotencyKeys.length == 1) {
      throw StateError('CONNECTION_LOST_AFTER_SEND');
    }
    if (keyReusedOnce && idempotencyKeys.length == 1) {
      throw StateError('IDEMPOTENCY_KEY_REUSED: used for another package');
    }
    final serverPrice = currentPrice;
    if (serverPrice != null && serverPrice != expectedPrice) {
      throw StateError('PRICE_CHANGED: expected price is stale');
    }
    await gate?.future;
    return {
      'purchase_id': 'purchase-1',
      'package_id': packageId,
      'status': 'completed',
      'amount_paid': expectedPrice,
    };
  }

  @override
  Future<PurchaseOrder?> getMyPurchaseOrder(String purchaseId) async => null;

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
