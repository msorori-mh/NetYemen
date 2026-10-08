import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/app/app_shell.dart';
import 'package:netyemen/core/config/app_config.dart';
import 'package:netyemen/core/config/app_config_provider.dart';
import 'package:netyemen/features/auth/presentation/customer_auth_providers.dart';
import 'package:netyemen/features/auth/presentation/customer_session_providers.dart';
import 'package:netyemen/features/security/presentation/pin_entry_screen.dart';
import 'package:netyemen/features/security/presentation/pin_providers.dart';

import '../../fakes/fake_customer_auth_repository.dart';
import '../../fakes/fake_pin_repository.dart';

Widget _buildScreen({
  required FakeCustomerAuthRepository auth,
  required FakePinRepository pins,
}) {
  return ProviderScope(
    overrides: [
      appConfigProvider.overrideWithValue(AppConfig.demo),
      currentUserProvider.overrideWithValue(null),
      currentUserRolesProvider.overrideWith((ref) async => const []),
      customerAuthRepositoryProvider.overrideWithValue(auth),
      pinRepositoryProvider.overrideWithValue(pins),
    ],
    child: const MaterialApp(home: PinEntryScreen()),
  );
}

void main() {
  testWidgets('a customer who forgot the PIN can sign out instead of being stuck',
      (tester) async {
    final auth = FakeCustomerAuthRepository();
    final pins = FakePinRepository(verifyResult: false);

    await tester.pumpWidget(_buildScreen(auth: auth, pins: pins));
    await tester.pump();

    final signOut = find.byKey(const Key('pin-entry-sign-out'));
    expect(signOut, findsOneWidget);

    await tester.ensureVisible(signOut);
    await tester.tap(signOut);
    await tester.pumpAndSettle();

    expect(auth.signOutCalled, isTrue);
    expect(find.byType(PinEntryScreen), findsNothing);
    expect(find.byType(AppShell), findsOneWidget);
    expect(pins.verifiedPins, isEmpty, reason: 'no PIN was needed to leave');
  });

  testWidgets('a failed sign-out keeps the PIN screen and explains why', (
    tester,
  ) async {
    final auth = FakeCustomerAuthRepository()
      ..signOutException = Exception('network down');
    final pins = FakePinRepository();

    await tester.pumpWidget(_buildScreen(auth: auth, pins: pins));
    await tester.pump();

    final signOut = find.byKey(const Key('pin-entry-sign-out'));
    await tester.ensureVisible(signOut);
    await tester.tap(signOut);
    await tester.pump();
    await tester.pump();

    expect(auth.signOutCalled, isTrue);
    expect(find.byType(PinEntryScreen), findsOneWidget);
    expect(find.textContaining('تعذّر تسجيل الخروج'), findsOneWidget);
    expect(find.byType(AppShell), findsNothing);
  });

  testWidgets('a wrong PIN is rejected and the field is cleared', (
    tester,
  ) async {
    final auth = FakeCustomerAuthRepository();
    final pins = FakePinRepository(verifyResult: false);

    await tester.pumpWidget(_buildScreen(auth: auth, pins: pins));
    await tester.pump();

    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();
    await tester.pump();

    expect(pins.verifiedPins, ['123456']);
    expect(find.text('الرمز السري غير صحيح'), findsOneWidget);
    expect(find.byType(PinEntryScreen), findsOneWidget);
    expect(auth.signOutCalled, isFalse);
  });
}
