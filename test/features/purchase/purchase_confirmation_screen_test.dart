import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/core/config/app_config.dart';
import 'package:netyemen/core/config/app_config_provider.dart';
import 'package:netyemen/core/utils/money_format.dart';
import 'package:netyemen/features/packages/domain/entities.dart';
import 'package:netyemen/features/purchase/data/fake_purchase_repository.dart';
import 'package:netyemen/features/purchase/presentation/purchase_confirmation_screen.dart';
import 'package:netyemen/features/purchase/presentation/purchase_providers.dart';

const _packageA = NetworkPackage(
  id: 'pkg-a',
  networkId: 'net-1',
  name: 'باقة أ',
  price: 1000,
  currency: 'YER',
  packageType: 'time',
  status: 'active',
  isPublic: true,
  sortOrder: 1,
);

const _packageB = NetworkPackage(
  id: 'pkg-b',
  networkId: 'net-1',
  name: 'باقة ب',
  price: 2500,
  currency: 'YER',
  packageType: 'time',
  status: 'active',
  isPublic: true,
  sortOrder: 2,
);

Widget _host(
  ValueNotifier<NetworkPackage> selected,
  FakePurchaseRepository repository,
) {
  return ProviderScope(
    overrides: [
      appConfigProvider.overrideWithValue(AppConfig.demo),
      purchaseRepositoryProvider.overrideWithValue(repository),
    ],
    child: MaterialApp(
      home: ValueListenableBuilder<NetworkPackage>(
        valueListenable: selected,
        builder: (_, package, __) => PurchaseConfirmationScreen(
          key: ValueKey(package.id),
          package: package,
          networkName: 'شبكة تجريبية',
        ),
      ),
    ),
  );
}

Future<void> _settleRepository(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

void main() {
  testWidgets('confirmation shows the exact whole-YER price that is charged', (
    tester,
  ) async {
    final selected = ValueNotifier<NetworkPackage>(_packageA);
    addTearDown(selected.dispose);

    await tester.pumpWidget(_host(selected, FakePurchaseRepository()));
    await tester.pump();
    await tester.pump();

    expect(_packageA.displayPrice, '1,000 YER');
    expect(_packageA.displayPrice, formatYer(_packageA.price));
    expect(find.text('السعر: ${_packageA.displayPrice}'), findsOneWidget);
  });

  testWidgets('a price change is explained and never retried blindly', (
    tester,
  ) async {
    final selected = ValueNotifier<NetworkPackage>(_packageA);
    addTearDown(selected.dispose);
    final repository = FakePurchaseRepository()..currentPriceOverride = 1500;

    await tester.pumpWidget(_host(selected, repository));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const Key('purchase-confirm')));
    await _settleRepository(tester);

    expect(find.byKey(const Key('purchase-submit-error')), findsOneWidget);
    expect(find.textContaining('تغيّر سعر'), findsOneWidget);
    expect(
      find.byKey(const Key('purchase-price-changed-back')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('purchase-confirm')), findsNothing);
    expect(repository.orders, isEmpty);
  });

  testWidgets('an error from one package is not shown on another package', (
    tester,
  ) async {
    final selected = ValueNotifier<NetworkPackage>(_packageA);
    addTearDown(selected.dispose);
    final repository = FakePurchaseRepository()..currentPriceOverride = 1500;

    await tester.pumpWidget(_host(selected, repository));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const Key('purchase-confirm')));
    await _settleRepository(tester);
    expect(find.byKey(const Key('purchase-submit-error')), findsOneWidget);

    // The customer leaves package A and opens package B.
    selected.value = _packageB;
    await tester.pump();
    await tester.pump();

    expect(find.text('السعر: ${_packageB.displayPrice}'), findsOneWidget);
    expect(find.byKey(const Key('purchase-submit-error')), findsNothing);
    expect(
      find.widgetWithText(ElevatedButton, 'تأكيد الشراء'),
      findsOneWidget,
    );
  });
}
