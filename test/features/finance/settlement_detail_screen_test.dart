import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/core/config/app_config.dart';
import 'package:netyemen/core/config/app_config_provider.dart';
import 'package:netyemen/features/finance/data/fake_finance_repository.dart';
import 'package:netyemen/features/finance/data/finance_providers.dart';
import 'package:netyemen/features/finance/presentation/settlement_detail_screen.dart';

class _RecordingFinanceRepository extends FakeFinanceRepository {
  final List<String> paidReferences = [];
  final List<String> cancelReasons = [];

  @override
  Future<Map<String, dynamic>> markSettlementPaid(
    String batchId, {
    required String paymentReference,
  }) async {
    paidReferences.add(paymentReference);
    return {'id': batchId, 'status': 'paid'};
  }

  @override
  Future<Map<String, dynamic>> cancelSettlementBatch(
    String batchId, {
    required String reason,
  }) async {
    cancelReasons.add(reason);
    return {'id': batchId, 'status': 'cancelled', 'released_items': 2};
  }
}

Map<String, dynamic> _batch(String status, {int net = 4850}) {
  return {
    'id': 'batch-1',
    'status': status,
    'network_name': 'شبكة تجريبية',
    'owner_name': 'مالك تجريبي',
    'period_start': '2026-09-01',
    'period_end': '2026-09-30',
    'gross_sales': 5000,
    'total_commission': 150,
    'total_refunds': 0,
    'total_adjustments': 0,
    'net_settlement': net,
  };
}

Widget _host(Map<String, dynamic> batch, FakeFinanceRepository repository) {
  return ProviderScope(
    overrides: [
      appConfigProvider.overrideWithValue(AppConfig.demo),
      financeRepositoryProvider.overrideWithValue(repository),
    ],
    child: MaterialApp(home: SettlementDetailScreen(batch: batch)),
  );
}

void main() {
  testWidgets('marking paid requires a payment reference', (tester) async {
    final repository = _RecordingFinanceRepository();
    await tester.pumpWidget(_host(_batch('approved'), repository));

    final markPaid = find.byKey(const Key('settlement-mark-paid'));
    await tester.ensureVisible(markPaid);
    await tester.tap(markPaid);
    await tester.pump();

    expect(find.textContaining('مرجع الدفع مطلوب'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(repository.paidReferences, isEmpty);

    await tester.enterText(
      find.byKey(const Key('settlement-payment-reference')),
      '  TRX-2026-001  ',
    );
    await tester.ensureVisible(markPaid);
    await tester.tap(markPaid);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'تسجيل الدفع'));
    await tester.pumpAndSettle();

    expect(repository.paidReferences, ['TRX-2026-001']);
    expect(find.text('تم التسجيل كمدفوع'), findsOneWidget);
  });

  testWidgets('cancelling a draft batch requires a reason', (tester) async {
    final repository = _RecordingFinanceRepository();
    await tester.pumpWidget(_host(_batch('draft'), repository));

    final cancel = find.byKey(const Key('settlement-cancel'));
    final confirm = find.byKey(const Key('settlement-cancel-confirm'));

    await tester.ensureVisible(cancel);
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(repository.cancelReasons, isEmpty);
    expect(find.text('سبب الإلغاء مطلوب لإلغاء الدفعة.'), findsOneWidget);

    await tester.tap(cancel);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('settlement-cancel-reason')),
      ' created for the wrong period ',
    );
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(repository.cancelReasons, ['created for the wrong period']);
  });

  testWidgets('a paid batch offers no further action', (tester) async {
    final repository = _RecordingFinanceRepository();
    await tester.pumpWidget(_host(_batch('paid'), repository));

    expect(find.byKey(const Key('settlement-cancel')), findsNothing);
    expect(find.byKey(const Key('settlement-mark-paid')), findsNothing);
    expect(find.byKey(const Key('settlement-negative-net')), findsNothing);
  });

  testWidgets('a negative net is shown as owed by the owner', (tester) async {
    final repository = _RecordingFinanceRepository();
    await tester.pumpWidget(_host(_batch('approved', net: -300), repository));

    expect(find.text('-300'), findsOneWidget);
    expect(find.byKey(const Key('settlement-negative-net')), findsOneWidget);
  });

  test('maps settlement refusals to specific messages', () {
    expect(
      settlementErrorMessage(StateError('PAYMENT_REFERENCE_REQUIRED')),
      contains('مرجع الدفع مطلوب'),
    );
    expect(
      settlementErrorMessage(StateError('REASON_REQUIRED')),
      contains('سبب الإلغاء'),
    );
    expect(
      settlementErrorMessage(StateError('INVALID_STATE: paid')),
      contains('حالة الدفعة'),
    );
    expect(
      settlementErrorMessage(Exception('socket closed')),
      isNot(contains('socket')),
    );
  });

  test('demo repository mirrors the server settlement rules', () async {
    final repository = FakeFinanceRepository();
    await repository.createSettlementBatch(
      periodStart: DateTime(2026, 9),
      periodEnd: DateTime(2026, 9, 30),
    );
    final batches = await repository.getFinanceSettlementBatches(null);
    final batchId = batches.single['id'] as String;

    await expectLater(
      repository.cancelSettlementBatch(batchId, reason: '  '),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      repository.markSettlementPaid(batchId, paymentReference: 'TRX-9'),
      throwsA(isA<StateError>()),
      reason: 'a draft batch cannot be paid',
    );

    await repository.approveSettlementBatch(batchId);
    await expectLater(
      repository.markSettlementPaid(batchId, paymentReference: '  '),
      throwsA(isA<StateError>()),
    );
    final paid = await repository.markSettlementPaid(
      batchId,
      paymentReference: 'TRX-9',
    );
    expect(paid['status'], 'paid');

    await expectLater(
      repository.cancelSettlementBatch(batchId, reason: 'too late'),
      throwsA(isA<StateError>()),
    );
  });
}
