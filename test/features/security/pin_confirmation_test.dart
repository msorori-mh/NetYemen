import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/core/config/app_config.dart';
import 'package:netyemen/core/config/app_config_provider.dart';
import 'package:netyemen/features/security/presentation/pin_confirmation.dart';
import 'package:netyemen/features/security/presentation/pin_providers.dart';

import '../../fakes/fake_pin_repository.dart';

void main() {
  const configuredConfig = AppConfig(
    supabaseUrl: 'http://127.0.0.1:54321',
    supabasePublishableKey: 'test-publishable-key',
  );

  bool? outcome;

  Widget buildHarness(FakePinRepository pins, {AppConfig? config}) {
    outcome = null;
    return ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(config ?? configuredConfig),
        pinRepositoryProvider.overrideWithValue(pins),
      ],
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const Key('protected-action'),
                onPressed: () async {
                  outcome = await confirmAccountPin(context, ref);
                },
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('a recent server verification needs no PIN prompt', (
    tester,
  ) async {
    final pins = FakePinRepository(recentlyVerified: true);
    await tester.pumpWidget(buildHarness(pins));

    await tester.tap(find.byKey(const Key('protected-action')));
    await tester.pumpAndSettle();

    expect(find.byType(PinConfirmDialog), findsNothing);
    expect(outcome, isTrue);
    expect(pins.verifiedPins, isEmpty);
  });

  testWidgets('asks for the PIN, rejects a wrong one, accepts the right one', (
    tester,
  ) async {
    final pins = FakePinRepository(recentlyVerified: false, verifyResult: false);
    await tester.pumpWidget(buildHarness(pins));

    await tester.tap(find.byKey(const Key('protected-action')));
    await tester.pumpAndSettle();
    expect(find.byType(PinConfirmDialog), findsOneWidget);

    await tester.enterText(find.byKey(const Key('pin-confirm-field')), '111111');
    await tester.tap(find.byKey(const Key('pin-confirm-submit')));
    await tester.pumpAndSettle();
    expect(find.text('الرمز السري غير صحيح'), findsOneWidget);
    expect(outcome, isNull);

    pins.verifyResult = true;
    await tester.enterText(find.byKey(const Key('pin-confirm-field')), '٢٤٦٨١٠');
    await tester.tap(find.byKey(const Key('pin-confirm-submit')));
    await tester.pumpAndSettle();

    expect(find.byType(PinConfirmDialog), findsNothing);
    expect(outcome, isTrue);
    expect(pins.verifiedPins, ['111111', '246810']);
  });

  testWidgets('cancelling the prompt stops the operation', (tester) async {
    final pins = FakePinRepository(recentlyVerified: false);
    await tester.pumpWidget(buildHarness(pins));

    await tester.tap(find.byKey(const Key('protected-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pin-confirm-cancel')));
    await tester.pumpAndSettle();

    expect(outcome, isFalse);
    expect(pins.verifiedPins, isEmpty);
  });

  testWidgets('a locked PIN shows the lockout message', (tester) async {
    final pins = FakePinRepository(recentlyVerified: false)
      ..verifyError = Exception('PIN_LOCKED');
    await tester.pumpWidget(buildHarness(pins));

    await tester.tap(find.byKey(const Key('protected-action')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('pin-confirm-field')), '123456');
    await tester.tap(find.byKey(const Key('pin-confirm-submit')));
    await tester.pumpAndSettle();

    expect(find.text('محاولات كثيرة — حاول بعد 15 دقيقة'), findsOneWidget);
    expect(outcome, isNull);
  });

  testWidgets('demo builds have no PIN and continue', (tester) async {
    final pins = FakePinRepository(recentlyVerified: false);
    await tester.pumpWidget(buildHarness(pins, config: AppConfig.demo));

    await tester.tap(find.byKey(const Key('protected-action')));
    await tester.pumpAndSettle();

    expect(find.byType(PinConfirmDialog), findsNothing);
    expect(outcome, isTrue);
  });
}
