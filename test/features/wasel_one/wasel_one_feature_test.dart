import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/core/config/app_config.dart';
import 'package:netyemen/core/config/app_config_provider.dart';
import 'package:netyemen/features/auth/presentation/customer_session_providers.dart';
import 'package:netyemen/features/wasel_one/data/fake_wasel_one_repository.dart';
import 'package:netyemen/features/wasel_one/domain/entities.dart';
import 'package:netyemen/features/wasel_one/presentation/wasel_one_screen.dart';

void main() {
  test('federated plan decodes partner count and limits', () {
    final plan = FederatedAccessPlan.fromJson({
      'id': 'plan-1',
      'name': 'واصل ون',
      'retail_price': 500,
      'currency': 'YER',
      'validity_seconds': 3600,
      'quota_bytes': 1048576,
      'speed_limit_kbps': 4096,
      'max_concurrent_sessions': 1,
      'federated_plan_networks': [
        {'count': 8},
      ],
    });

    expect(plan.partnerCount, 8);
    expect(plan.validity, const Duration(hours: 1));
    expect(plan.quotaBytes, 1048576);
  });

  test(
    'demo repository exposes a usable entitlement and one-time credential',
    () async {
      final repository = FakeWaselOneRepository();
      final plans = await repository.getPublicPlans();
      final entitlements = await repository.getMyEntitlements();
      final credential = await repository.issueAccessCredential(
        entitlements.single.id,
      );
      final purchase = await repository.purchasePlan(
        planId: plans.first.id,
        idempotencyKey: 'demo-key-1',
      );
      final replay = await repository.purchasePlan(
        planId: plans.first.id,
        idempotencyKey: 'demo-key-1',
      );

      expect(plans, hasLength(3));
      expect(entitlements.single.isUsable, isTrue);
      expect(credential.username, startsWith('w1-'));
      expect(credential.password, isNotEmpty);
      expect(purchase.isCompleted, isTrue);
      expect(replay.purchaseId, purchase.purchaseId);
      expect(replay.replayed, isTrue);
    },
  );

  testWidgets('WASEL One demo shows plans and issues temporary credentials', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(AppConfig.demo),
          currentUserProvider.overrideWithValue(null),
        ],
        child: const MaterialApp(home: WaselOneScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('إنترنت بلا حدود الشبكة'), findsOneWidget);
    expect(find.byKey(const Key('wasel-one-demo-banner')), findsOneWidget);
    expect(find.text('واصل ون — يوم'), findsWidgets);

    final issueButton = find.byKey(const Key('wasel-one-issue-credential'));
    await tester.ensureVisible(issueButton);
    await tester.tap(issueButton);
    await tester.pumpAndSettle();

    expect(find.text('بيانات الدخول المؤقتة'), findsOneWidget);
    expect(find.text('w1-0123456789abcdef01234567'), findsOneWidget);
    expect(find.text('TEST-ONLY-482731'), findsOneWidget);
  });

  testWidgets('WASEL One demo purchases and activates a selected plan', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(AppConfig.demo),
          currentUserProvider.overrideWithValue(null),
        ],
        child: const MaterialApp(home: WaselOneScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final buyButton = find.byKey(const Key('wasel-one-buy-demo-one-hour'));
    await tester.scrollUntilVisible(buyButton, 300);
    await tester.tap(buyButton);
    await tester.pumpAndSettle();

    expect(find.text('تأكيد شراء باقة واصل ون'), findsOneWidget);
    await tester.tap(find.byKey(const Key('wasel-one-confirm-purchase')));
    await tester.pumpAndSettle();

    expect(find.text('تم تفعيل الباقة'), findsOneWidget);
    expect(find.textContaining('أصبحت صلاحية الدخول جاهزة'), findsOneWidget);
    await tester.tap(find.byKey(const Key('wasel-one-purchase-done')));
    await tester.pumpAndSettle();

    expect(find.text('واصل ون — ساعة'), findsWidgets);
  });
}
