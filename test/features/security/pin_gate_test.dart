import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/features/auth/presentation/customer_session_providers.dart';
import 'package:netyemen/features/security/domain/pin_status.dart';
import 'package:netyemen/features/security/presentation/pin_entry_screen.dart';
import 'package:netyemen/features/security/presentation/pin_gate.dart';
import 'package:netyemen/features/security/presentation/pin_providers.dart';
import 'package:netyemen/features/security/presentation/pin_setup_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../fakes/fake_pin_repository.dart';

/// Minimal stand-in so the gate sees a signed-in user without Supabase.
class _FakeUser implements User {
  @override
  String get id => 'user-1';

  @override
  noSuchMethod(Invocation invocation) => null;
}

Future<void> _pumpGate(WidgetTester tester, FakePinRepository repo) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        pinRepositoryProvider.overrideWithValue(repo),
        currentUserProvider.overrideWithValue(_FakeUser()),
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
}
