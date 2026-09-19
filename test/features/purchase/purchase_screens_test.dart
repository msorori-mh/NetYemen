import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/core/config/app_config.dart';
import 'package:netyemen/features/purchase/data/fake_purchase_repository.dart';
import 'package:netyemen/features/purchase/domain/entities.dart';
import 'package:netyemen/features/purchase/presentation/card_reveal_screen.dart';
import 'package:netyemen/features/purchase/presentation/purchase_detail_screen.dart';
import 'package:netyemen/features/purchase/presentation/purchase_history_screen.dart';
import 'package:netyemen/features/purchase/presentation/purchase_providers.dart';
import 'package:netyemen/features/purchase/presentation/purchase_result_screen.dart';
import 'package:netyemen/providers/app_providers.dart';

void main() {
  testWidgets('customer purchase history excludes owner finance data', (
    tester,
  ) async {
    final repository = FakePurchaseRepository();
    await repository.purchasePackage(
      packageId: 'package-1',
      idempotencyKey: 'history-key',
    );

    await tester.pumpWidget(
      _buildScreen(const PurchaseHistoryScreen(), repository),
    );
    await tester.pumpAndSettle();

    expect(find.text('باقة تجريبية'), findsOneWidget);
    expect(find.text('مكتمل'), findsOneWidget);
    expect(find.textContaining('العمولة'), findsNothing);
    expect(find.textContaining('الصافي'), findsNothing);
  });

  testWidgets('purchase detail reveals, copies, and clears card safely', (
    tester,
  ) async {
    String? clipboardText;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboardText = (call.arguments as Map<dynamic, dynamic>)['text']
            as String?;
        return null;
      }
      if (call.method == 'Clipboard.getData') {
        return <String, dynamic>{'text': clipboardText};
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    final repository = FakePurchaseRepository();
    final result = await repository.purchasePackage(
      packageId: 'package-1',
      idempotencyKey: 'detail-key',
    );

    await tester.pumpWidget(
      _buildScreen(
        PurchaseDetailScreen(purchaseId: result['purchase_id'] as String),
        repository,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('المبلغ المدفوع: '), findsOneWidget);
    expect(find.textContaining('نسبة العمولة'), findsNothing);
    expect(find.textContaining('الصافي لصاحب الشبكة'), findsNothing);

    await tester.tap(find.byKey(const Key('purchase-reveal-card')));
    await tester.pumpAndSettle();

    expect(find.text('••••••••••••'), findsOneWidget);
    expect(find.text('DEMO-CARD-123456'), findsNothing);

    await tester.tap(find.byKey(const Key('card-secret-visibility')));
    await tester.pump();
    expect(find.text('DEMO-CARD-123456'), findsOneWidget);

    await tester.tap(find.byKey(const Key('card-secret-copy')));
    await tester.pump();
    expect(
      (await Clipboard.getData(Clipboard.kTextPlain))?.text,
      'DEMO-CARD-123456',
    );

    await tester.pump(const Duration(seconds: 60));
    await tester.pump();
    expect(
      (await Clipboard.getData(Clipboard.kTextPlain))?.text,
      anyOf(isNull, isEmpty),
    );
  });

  testWidgets('missing dispute deadline fails closed', (tester) async {
    await tester.pumpWidget(
      _buildScreen(
        const CardRevealScreen(
          revealedInfo: RevealedCardInfo(
            purchaseId: 'purchase-1',
            plaintext: 'CARD-1',
          ),
        ),
        FakePurchaseRepository(),
      ),
    );
    await tester.pump();

    expect(find.text('تعذر التحقق من مهلة النزاع.'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('successful purchase result links to its card detail', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildScreen(
        const PurchaseResultScreen(
          success: true,
          purchaseResult: {
            'purchase_id': 'purchase-1',
            'amount_paid': 1000,
            'fulfillment_status': 'pending_secret',
          },
          packageName: 'باقة',
        ),
        FakePurchaseRepository(),
      ),
    );

    expect(
      find.byKey(const Key('purchase-result-open-detail')),
      findsOneWidget,
    );
    expect(find.text('عرض تفاصيل العملية والكرت'), findsOneWidget);
  });

  testWidgets('successful dispute disables a second submission', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildScreen(
        CardRevealScreen(
          revealedInfo: RevealedCardInfo(
            purchaseId: 'purchase-1',
            plaintext: 'CARD-1',
            disputeDeadline: DateTime.now().add(const Duration(minutes: 10)),
          ),
        ),
        FakePurchaseRepository(),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'الكرت لا يعمل');
    await tester.tap(find.text('الكرت غير صالح - فتح نزاع'));
    await tester.pumpAndSettle();

    expect(find.text('تم فتح النزاع بنجاح'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('تم تسجيل بلاغ الكرت غير الصالح.'), findsOneWidget);
  });
}

Widget _buildScreen(Widget screen, FakePurchaseRepository repository) {
  return ProviderScope(
    overrides: [
      appConfigProvider.overrideWithValue(AppConfig.demo),
      purchaseRepositoryProvider.overrideWithValue(repository),
    ],
    child: MaterialApp(home: screen),
  );
}
