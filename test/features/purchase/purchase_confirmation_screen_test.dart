import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/core/config/app_config.dart';
import 'package:netyemen/core/config/app_config_provider.dart';
import 'package:netyemen/features/packages/domain/entities.dart';
import 'package:netyemen/features/purchase/data/fake_purchase_repository.dart';
import 'package:netyemen/features/purchase/presentation/purchase_confirmation_screen.dart';
import 'package:netyemen/features/purchase/presentation/purchase_providers.dart';

void main() {
  testWidgets('an error from another package is not shown', (tester) async {
    final repository = _FailingPurchaseRepository();
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(AppConfig.demo),
        purchaseRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    Future<void> open(NetworkPackage package) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            key: ValueKey(package.id),
            home: PurchaseConfirmationScreen(
              package: package,
              networkName: 'شبكة',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await open(_package('package-a'));
    await tester.tap(find.widgetWithText(ElevatedButton, 'تأكيد الشراء'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('purchase-submit-error')), findsOneWidget);

    await open(_package('package-b'));
    expect(find.byKey(const Key('purchase-submit-error')), findsNothing);
    expect(
      find.widgetWithText(ElevatedButton, 'تأكيد الشراء'),
      findsOneWidget,
    );

    // Returning to the failed package still offers the safe retry.
    await open(_package('package-a'));
    expect(find.byKey(const Key('purchase-submit-error')), findsOneWidget);
    expect(
      find.widgetWithText(ElevatedButton, 'إعادة المحاولة بأمان'),
      findsOneWidget,
    );
  });
}

NetworkPackage _package(String id) => NetworkPackage(
      id: id,
      networkId: 'network-1',
      name: 'باقة $id',
      price: 500,
      currency: 'YER',
      packageType: 'card',
      status: 'active',
      isPublic: true,
      sortOrder: 0,
    );

class _FailingPurchaseRepository extends FakePurchaseRepository {
  @override
  Future<Map<String, dynamic>> purchasePackage({
    required String packageId,
    required String idempotencyKey,
  }) async {
    throw StateError('INSUFFICIENT_BALANCE');
  }
}
