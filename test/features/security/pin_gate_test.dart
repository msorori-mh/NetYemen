import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/core/config/app_config.dart';
import 'package:netyemen/core/config/app_config_provider.dart';
import 'package:netyemen/features/auth/presentation/customer_auth_providers.dart';
import 'package:netyemen/features/auth/presentation/customer_session_providers.dart';
import 'package:netyemen/features/auth/presentation/login_screen.dart';
import 'package:netyemen/features/security/domain/pin_status.dart';
import 'package:netyemen/features/security/presentation/pin_entry_screen.dart';
import 'package:netyemen/features/security/presentation/pin_gate.dart';
import 'package:netyemen/features/security/presentation/pin_providers.dart';
import 'package:netyemen/features/security/presentation/pin_setup_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../fakes/fake_customer_auth_repository.dart';
import '../../fakes/fake_pin_repository.dart';

/// Minimal stand-in so the gate sees a signed-in user without Supabase.
class _FakeUser implements User {
  @override
  String get id => 'user-1';

  @override
  noSuchMethod(Invocation invocation) => null;
}

Future<void> _pumpGate(
  WidgetTester tester,
  FakePinRepository repo, {
  FakeCustomerAuthRepository? auth,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(AppConfig.demo),
        pinRepositoryProvider.overrideWithValue(repo),
        currentUserProvider.overrideWithValue(_FakeUser()),
        customerAuthRepositoryProvider.overrideWithValue(
          auth ?? FakeCustomerAuthRepository(),
        ),
      ],
      child: const MaterialApp(home: PinGate()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('no PIN yet routes to setup', (tester) async {
    await _pumpGate(tester, FakePinRepository(status: PinStatus.notSet));
    expect(find.byType(PinSetupScreen), findsOneWidget);
  });

  testWidgets('PIN set on an untrusted device demands entry', (tester) async {
    await _pumpGate(
      tester,
      FakePinRepository(status: PinStatus.setAndUntrusted),
    );
    expect(find.byType(PinEntryScreen), findsOneWidget);
  });

  testWidgets('gate FAILS CLOSED: a resolve error never grants access',
      (tester) async {
    await _pumpGate(
      tester,
      FakePinRepository(resolveError: Exception('network down')),
    );

    // The whole point: an error must not let anyone past the gate.
    expect(find.byType(PinSetupScreen), findsNothing);
    expect(find.byType(PinEntryScreen), findsNothing);
    expect(find.byKey(const Key('pin-gate-retry')), findsOneWidget);
  });

  testWidgets('gate error offers sign-out back to the login screen',
      (tester) async {
    final auth = FakeCustomerAuthRepository();
    await _pumpGate(
      tester,
      FakePinRepository(resolveError: Exception('network down')),
      auth: auth,
    );

    expect(find.byKey(const Key('pin-gate-retry')), findsOneWidget);
    await tester.tap(find.byKey(const Key('pin-sign-out')));
    await tester.pumpAndSettle();

    expect(auth.signOutCalled, isTrue);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(PinGate), findsNothing);
  });

  for (final status in [PinStatus.notSet, PinStatus.setAndUntrusted]) {
    testWidgets('PIN screen for $status can sign out', (tester) async {
      final auth = FakeCustomerAuthRepository();
      await _pumpGate(tester, FakePinRepository(status: status), auth: auth);

      await tester.tap(find.byKey(const Key('pin-sign-out')));
      await tester.pumpAndSettle();

      expect(auth.signOutCalled, isTrue);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(PinSetupScreen), findsNothing);
      expect(find.byType(PinEntryScreen), findsNothing);
    });
  }

  testWidgets('failed sign-out keeps the user on the PIN screen',
      (tester) async {
    final auth = FakeCustomerAuthRepository()
      ..signOutException = Exception('offline');
    await _pumpGate(
      tester,
      FakePinRepository(status: PinStatus.setAndUntrusted),
      auth: auth,
    );

    await tester.tap(find.byKey(const Key('pin-sign-out')));
    await tester.pumpAndSettle();

    expect(find.byType(PinEntryScreen), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
  });
}
