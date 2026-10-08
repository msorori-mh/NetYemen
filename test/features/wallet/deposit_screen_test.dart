import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/core/config/app_config.dart';
import 'package:netyemen/core/config/app_config_provider.dart';
import 'package:netyemen/features/wallet/data/fake_wallet_repository.dart';
import 'package:netyemen/features/wallet/domain/entities.dart';
import 'package:netyemen/features/wallet/presentation/deposit_screen.dart';
import 'package:netyemen/features/wallet/presentation/wallet_providers.dart';

void main() {
  late FakeWalletRepository repository;

  Widget buildScreen() {
    return ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(AppConfig.demo),
        walletRepositoryProvider.overrideWithValue(repository),
      ],
      child: const MaterialApp(home: DepositScreen()),
    );
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  setUp(() => repository = FakeWalletRepository());

  testWidgets('shows the destination account with a copy action', (
    tester,
  ) async {
    String? clipboardText;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboardText =
            (call.arguments as Map<dynamic, dynamic>)['text'] as String?;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.pumpWidget(buildScreen());
    await settle(tester);

    expect(
      find.byKey(const Key('deposit-destination-details')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('deposit-account-identifier')), findsOneWidget);
    expect(find.text('Transfer to demo account'), findsOneWidget);
    expect(find.textContaining('OD-FIN'), findsNothing);

    await tester.tap(find.byKey(const Key('deposit-copy-account-identifier')));
    await tester.pump();

    expect(clipboardText, 'DEMO-123456');
  });

  testWidgets('requires the transfer reference before sending', (tester) async {
    await tester.pumpWidget(buildScreen());
    await settle(tester);

    await tester.enterText(
      find.byKey(const Key('deposit-amount-field')),
      '5000',
    );
    await tester.ensureVisible(find.byKey(const Key('deposit-submit')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('deposit-submit')));
    await settle(tester);

    expect(
      find.text('رقم المرجع مطلوب. انسخه من إيصال التحويل.'),
      findsOneWidget,
    );
    expect(await _depositCount(tester, repository), 1);
  });

  testWidgets('accepts an amount typed with Arabic-Indic digits', (
    tester,
  ) async {
    await tester.pumpWidget(buildScreen());
    await settle(tester);

    await tester.enterText(
      find.byKey(const Key('deposit-amount-field')),
      '٥٠٠٠',
    );
    await tester.enterText(
      find.byKey(const Key('deposit-reference-field')),
      'REF-900',
    );
    await tester.ensureVisible(find.byKey(const Key('deposit-submit')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('deposit-submit')));
    await settle(tester);

    final shown = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data)
        .toList();
    expect(
      find.byKey(const Key('deposit-message')),
      findsOneWidget,
      reason: 'texts on screen: $shown',
    );
    expect(find.textContaining('5,000 YER'), findsOneWidget);

    final deposits = await _deposits(tester, repository);
    expect(deposits, hasLength(2));
    expect(deposits.last.amount, 5000);
    expect(deposits.last.proofReference, 'REF-900');
  });

  testWidgets('rejects a non-numeric amount with a field message', (
    tester,
  ) async {
    await tester.pumpWidget(buildScreen());
    await settle(tester);

    await tester.enterText(
      find.byKey(const Key('deposit-reference-field')),
      'REF-901',
    );
    await tester.ensureVisible(find.byKey(const Key('deposit-submit')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('deposit-submit')));
    await settle(tester);

    expect(
      find.text('أدخل مبلغاً صحيحاً بالريال اليمني (أرقام فقط).'),
      findsOneWidget,
    );
    expect(await _depositCount(tester, repository), 1);
  });
}

Future<int> _depositCount(
  WidgetTester tester,
  FakeWalletRepository repository,
) async {
  return (await _deposits(tester, repository)).length;
}

/// Reads the fake's deposits. The fake answers after a short delay, so the
/// test clock is advanced while the request is pending.
Future<List<DepositRequest>> _deposits(
  WidgetTester tester,
  FakeWalletRepository repository,
) async {
  final pending = repository.getMyDepositRequests();
  await tester.pump(const Duration(milliseconds: 300));
  return pending;
}
