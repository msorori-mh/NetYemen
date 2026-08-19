import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/core/config/app_config.dart';
import 'package:netyemen/features/finance/presentation/deposit_review_queue_screen.dart';
import 'package:netyemen/features/purchase/presentation/purchase_history_screen.dart';
import 'package:netyemen/features/wallet/presentation/deposit_history_screen.dart';
import 'package:netyemen/features/wallet/presentation/deposit_screen.dart';
import 'package:netyemen/features/wallet/presentation/wallet_screen.dart';
import 'package:netyemen/providers/app_providers.dart';

void main() {
  group('CommerceScreens', () {
    Widget buildScreen(Widget screen) {
      return ProviderScope(
        overrides: [appConfigProvider.overrideWithValue(AppConfig.demo)],
        child: MaterialApp(home: screen),
      );
    }

    testWidgets('WalletScreen renders balance and deposit actions', (
      tester,
    ) async {
      await tester.pumpWidget(buildScreen(const WalletScreen()));
      await tester.pumpAndSettle();

      expect(find.text('المحفظة'), findsOneWidget);
      expect(find.text('رصيد المحفظة'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'طلب إيداع'), findsOneWidget);
      expect(
        find.widgetWithText(OutlinedButton, 'سجل الإيداعات'),
        findsOneWidget,
      );
    });

    testWidgets('DepositScreen renders deposit form', (tester) async {
      await tester.pumpWidget(buildScreen(const DepositScreen()));
      await tester.pumpAndSettle();

      expect(find.text('طلب إيداع'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2));
      expect(
        find.widgetWithText(ElevatedButton, 'إرسال الطلب'),
        findsOneWidget,
      );
    });

    testWidgets('DepositHistoryScreen renders deposit list', (tester) async {
      await tester.pumpWidget(buildScreen(const DepositHistoryScreen()));
      await tester.pumpAndSettle();

      expect(find.text('سجل الإيداعات'), findsOneWidget);
      // Demo fake repository seeds one approved deposit with reference REF-123.
      expect(find.textContaining('REF-123'), findsOneWidget);
      expect(find.byType(ListTile), findsOneWidget);
    });

    testWidgets('PurchaseHistoryScreen renders empty state', (tester) async {
      await tester.pumpWidget(buildScreen(const PurchaseHistoryScreen()));
      await tester.pumpAndSettle();

      expect(find.text('سجل المشتريات'), findsOneWidget);
      expect(find.text('لا توجد مشتريات'), findsOneWidget);
    });

    testWidgets('DepositReviewQueueScreen renders finance queue', (
      tester,
    ) async {
      await tester.pumpWidget(buildScreen(const DepositReviewQueueScreen()));
      await tester.pumpAndSettle();

      expect(find.text('قبول الإيداعات'), findsOneWidget);
      // Demo fake repository seeds one submitted deposit with reference REF-001.
      expect(find.textContaining('REF-001'), findsOneWidget);
      expect(find.byType(ListTile), findsOneWidget);
    });
  });
}
