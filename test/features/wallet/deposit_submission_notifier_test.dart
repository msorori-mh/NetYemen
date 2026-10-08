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
          referenceNumber: 'REF-1',
        ),
        throwsA(isA<StateError>()),
      );
      final requestId = await notifier.submit(
        amount: 1000,
        paymentDestinationId: 'destination-1',
        referenceNumber: 'REF-1',
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
        referenceNumber: 'REF-1',
      );
      final second = notifier.submit(
        amount: 1000,
        paymentDestinationId: 'destination-1',
        referenceNumber: 'REF-1',
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
        referenceNumber: 'REF-1',
      );
      await notifier.submit(
        amount: 1000,
        paymentDestinationId: 'destination-1',
        referenceNumber: 'REF-1',
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
      referenceNumber: 'REF-1',
    );
    final replay = await repository.createDepositRequest(
      amount: 1000,
      idempotencyKey: 'key-1',
      paymentDestinationId: 'destination-1',
      referenceNumber: 'REF-1',
    );

    expect(replay, first);
    expect(await repository.getMyDepositRequests(), hasLength(2));
  });

  test('fake repository rejects an empty reference like the server', () async {
    final repository = FakeWalletRepository();

    await expectLater(
      repository.createDepositRequest(
        amount: 1000,
        idempotencyKey: 'key-2',
        paymentDestinationId: 'destination-1',
        referenceNumber: '   ',
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('INVALID_REFERENCE'),
        ),
      ),
    );
    expect(await repository.getMyDepositRequests(), hasLength(1));
  });

  test('notifier refuses a blank reference before any request', () async {
    final repository = _RecordingWalletRepository();
    final container = _container(repository);
    addTearDown(container.dispose);
    await container.read(depositSubmissionProvider.future);

    final notifier = container.read(depositSubmissionProvider.notifier);
    await expectLater(
      notifier.submit(
        amount: 1000,
        paymentDestinationId: 'destination-1',
        referenceNumber: '  ',
      ),
      throwsA(isA<StateError>()),
    );
    expect(repository.idempotencyKeys, isEmpty);
  });

  test('notifier sends the trimmed reference number', () async {
    final repository = _RecordingWalletRepository();
    final container = _container(repository);
    addTearDown(container.dispose);
    await container.read(depositSubmissionProvider.future);

    final notifier = container.read(depositSubmissionProvider.notifier);
    await notifier.submit(
      amount: 1000,
      paymentDestinationId: 'destination-1',
      referenceNumber: '  REF-77  ',
    );

    expect(repository.referenceNumbers, ['REF-77']);
  });

  group('depositErrorMessage', () {
    test('maps server refusals to specific messages', () {
      expect(
        depositErrorMessage(StateError('INVALID_REFERENCE: required')),
        contains('رقم المرجع مطلوب'),
      );
      expect(
        depositErrorMessage(StateError('INVALID_AMOUNT: positive')),
        contains('المبلغ غير صحيح'),
      );
      expect(
        depositErrorMessage(
          StateError('INVALID_PAYMENT_DESTINATION: inactive'),
        ),
        contains('وجهة الدفع'),
      );
      expect(
        depositErrorMessage(StateError('UNAUTHENTICATED: sign in')),
        contains('جلسة الدخول'),
      );
      expect(
        depositErrorMessage(StateError('INACTIVE_PROFILE: inactive')),
        contains('غير مفعّل'),
      );
    });

    test('keeps the connectivity message for real network errors only', () {
      final offline = depositErrorMessage(
        Exception('SocketException: Failed host lookup: example'),
      );
      final unknown = depositErrorMessage(StateError('SOMETHING_ELSE'));

      expect(offline, contains('تحقق من الاتصال'));
      expect(unknown, isNot(contains('تحقق من الاتصال')));
      for (final text in [offline, unknown]) {
        expect(text, isNot(contains('OD-FIN')));
        expect(text, isNot(contains('SOMETHING_ELSE')));
      }
    });
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
  final List<String> referenceNumbers = [];

  _RecordingWalletRepository({
    this.failFirstAttempt = false,
    this.gate,
  });

  @override
  Future<String> createDepositRequest({
    required int amount,
    required String idempotencyKey,
    required String paymentDestinationId,
    required String referenceNumber,
  }) async {
    idempotencyKeys.add(idempotencyKey);
    referenceNumbers.add(referenceNumber);
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
