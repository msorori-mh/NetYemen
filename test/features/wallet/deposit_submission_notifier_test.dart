import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/features/wallet/data/fake_wallet_repository.dart';
import 'package:netyemen/features/wallet/data/wallet_repository.dart';
import 'package:netyemen/features/wallet/domain/entities.dart';
import 'package:netyemen/features/wallet/presentation/wallet_providers.dart';

void main() {
  group('DepositSubmissionNotifier', () {
    test('reuses the same key after an ambiguous failure', () async {
      final repository = _RecordingWalletRepository(failFirstAttempt: true);
      final container = _container(repository);
      addTearDown(container.dispose);
      await container.read(depositSubmissionProvider.future);

      final notifier = container.read(depositSubmissionProvider.notifier);
      await expectLater(
        notifier.submit(
          amount: 1000,
          paymentDestinationId: 'destination-1',
          proofReference: 'REF-1',
        ),
        throwsA(isA<StateError>()),
      );
      final requestId = await notifier.submit(
        amount: 1000,
        paymentDestinationId: 'destination-1',
        proofReference: 'REF-1',
      );

      expect(requestId, 'deposit-1');
      expect(repository.idempotencyKeys, hasLength(2));
      expect(repository.idempotencyKeys[1], repository.idempotencyKeys[0]);
    });

    test('coalesces simultaneous submissions with the same payload', () async {
      final gate = Completer<void>();
      final repository = _RecordingWalletRepository(gate: gate);
      final container = _container(repository);
      addTearDown(container.dispose);
      await container.read(depositSubmissionProvider.future);

      final notifier = container.read(depositSubmissionProvider.notifier);
      final first = notifier.submit(
        amount: 1000,
        paymentDestinationId: 'destination-1',
      );
      final second = notifier.submit(
        amount: 1000,
        paymentDestinationId: 'destination-1',
      );
      gate.complete();

      expect(await Future.wait([first, second]), ['deposit-1', 'deposit-1']);
      expect(repository.idempotencyKeys, hasLength(1));
    });

    test('mints a new key after confirmed success', () async {
      final repository = _RecordingWalletRepository();
      final container = _container(repository);
      addTearDown(container.dispose);
      await container.read(depositSubmissionProvider.future);

      final notifier = container.read(depositSubmissionProvider.notifier);
      await notifier.submit(
        amount: 1000,
        paymentDestinationId: 'destination-1',
      );
      await notifier.submit(
        amount: 1000,
        paymentDestinationId: 'destination-1',
      );

      expect(repository.idempotencyKeys, hasLength(2));
      expect(
        repository.idempotencyKeys[1],
        isNot(repository.idempotencyKeys[0]),
      );
    });
  });

  test('fake repository replays a request without adding another deposit',
      () async {
    final repository = FakeWalletRepository();

    final first = await repository.createDepositRequest(
      amount: 1000,
      idempotencyKey: 'key-1',
      paymentDestinationId: 'destination-1',
    );
    final replay = await repository.createDepositRequest(
      amount: 1000,
      idempotencyKey: 'key-1',
      paymentDestinationId: 'destination-1',
    );

    expect(replay, first);
    expect(await repository.getMyDepositRequests(), hasLength(2));
  });
}

ProviderContainer _container(WalletRepository repository) {
  return ProviderContainer(
    overrides: [walletRepositoryProvider.overrideWithValue(repository)],
  );
}

class _RecordingWalletRepository implements WalletRepository {
  final bool failFirstAttempt;
  final Completer<void>? gate;
  final List<String> idempotencyKeys = [];

  _RecordingWalletRepository({
    this.failFirstAttempt = false,
    this.gate,
  });

  @override
  Future<String> createDepositRequest({
    required int amount,
    required String idempotencyKey,
    String? paymentDestinationId,
    String? proofReference,
  }) async {
    idempotencyKeys.add(idempotencyKey);
    if (failFirstAttempt && idempotencyKeys.length == 1) {
      throw StateError('CONNECTION_LOST_AFTER_SEND');
    }
    await gate?.future;
    return 'deposit-1';
  }

  @override
  Future<List<DepositChannel>> getActiveDepositChannels() async => const [];

  @override
  Future<List<DepositRequest>> getMyDepositRequests() async => const [];

  @override
  Future<WalletSummary> getMyWalletSummary() async => const WalletSummary(
        userId: 'user-1',
        balance: 0,
        currency: 'YER',
        accountStatus: 'active',
      );
}
