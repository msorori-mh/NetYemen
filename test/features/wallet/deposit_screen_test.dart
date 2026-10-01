import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/core/config/app_config.dart';
import 'package:netyemen/core/config/app_config_provider.dart';
import 'package:netyemen/core/utils/digits.dart';
import 'package:netyemen/features/wallet/data/wallet_repository.dart';
import 'package:netyemen/features/wallet/domain/entities.dart';
import 'package:netyemen/features/wallet/presentation/deposit_screen.dart';
import 'package:netyemen/features/wallet/presentation/wallet_providers.dart';

void main() {
  test('normalizeDigits converts Arabic-Indic and Persian digits', () {
    expect(normalizeDigits('١٢٣٤٥٦٧٨٩٠'), '1234567890');
    expect(normalizeDigits('۱۲۳۴۵۶۷۸۹۰'), '1234567890');
    expect(normalizeDigits('REF-٤٢'), 'REF-42');
  });

  test('parseDepositAmount accepts only positive whole numbers', () {
    expect(parseDepositAmount(' ١٥٠٠ '), 1500);
    expect(parseDepositAmount('۲۰۰'), 200);
    expect(parseDepositAmount('0'), isNull);
    expect(parseDepositAmount('-5'), isNull);
    expect(parseDepositAmount('abc'), isNull);
  });

  test('depositErrorMessage maps server codes to specific messages', () {
    expect(
      depositErrorMessage(Exception('INVALID_REFERENCE: required')),
      contains('رقم المرجع مطلوب'),
    );
    expect(
      depositErrorMessage(Exception('DUPLICATE_REFERENCE: credited')),
      contains('مستخدم في إيداع سابق'),
    );
    expect(
      depositErrorMessage(Exception('INVALID_AMOUNT: positive')),
      contains('أكبر من صفر'),
    );
    expect(
      depositErrorMessage(Exception('socket closed')),
      contains('أعد المحاولة'),
    );
  });

  testWidgets('reference number is required before submitting', (
    tester,
  ) async {
    final repository = _RecordingWalletRepository();
    await tester.pumpWidget(_buildScreen(repository));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('deposit-amount')), '١٥٠٠');
    await _selectDestination(tester);
    await tester.tap(find.widgetWithText(ElevatedButton, 'إرسال الطلب'));
    await tester.pumpAndSettle();

    expect(
      find.text('أدخل رقم المرجع الظاهر في إيصال التحويل'),
      findsOneWidget,
    );
    expect(repository.amounts, isEmpty);

    await tester.enterText(find.byKey(const Key('deposit-reference')), 'R-9');
    await tester.tap(find.widgetWithText(ElevatedButton, 'إرسال الطلب'));
    await tester.pumpAndSettle();

    expect(repository.amounts, [1500]);
    expect(repository.references, ['R-9']);
    expect(find.text('تم إرسال طلب الإيداع بنجاح'), findsOneWidget);
  });

  testWidgets('server error codes show a specific message', (tester) async {
    final repository = _RecordingWalletRepository(
      error: Exception('INVALID_REFERENCE: Reference number is required.'),
    );
    await tester.pumpWidget(_buildScreen(repository));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('deposit-amount')), '500');
    await tester.enterText(find.byKey(const Key('deposit-reference')), 'R-1');
    await _selectDestination(tester);
    await tester.tap(find.widgetWithText(ElevatedButton, 'إرسال الطلب'));
    await tester.pumpAndSettle();

    expect(
      find.text('رقم المرجع مطلوب. أدخل رقم المرجع الظاهر في إيصال التحويل.'),
      findsOneWidget,
    );
  });
}

Widget _buildScreen(WalletRepository repository) {
  return ProviderScope(
    overrides: [
      appConfigProvider.overrideWithValue(AppConfig.demo),
      walletRepositoryProvider.overrideWithValue(repository),
    ],
    child: const MaterialApp(home: DepositScreen()),
  );
}

Future<void> _selectDestination(WidgetTester tester) async {
  await tester.tap(find.byType(DropdownButton<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text('بنك الكريمي (تجريبي)').last);
  await tester.pumpAndSettle();
}

class _RecordingWalletRepository implements WalletRepository {
  final Object? error;
  final List<int> amounts = [];
  final List<String?> references = [];

  _RecordingWalletRepository({this.error});

  @override
  Future<String> createDepositRequest({
    required int amount,
    required String idempotencyKey,
    String? paymentDestinationId,
    String? proofReference,
  }) async {
    if (error != null) throw error!;
    amounts.add(amount);
    references.add(proofReference);
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
