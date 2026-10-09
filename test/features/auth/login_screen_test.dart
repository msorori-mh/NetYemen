import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/app/app_shell.dart';
import 'package:netyemen/core/config/app_config.dart';
import 'package:netyemen/core/config/app_config_provider.dart';
import 'package:netyemen/features/auth/presentation/customer_auth_providers.dart';
import 'package:netyemen/features/auth/presentation/customer_session_providers.dart';

import 'package:netyemen/features/auth/presentation/login_screen.dart';
import 'package:netyemen/features/auth/presentation/otp_screen.dart';
import 'package:netyemen/features/security/domain/pin_status.dart';
import 'package:netyemen/features/security/presentation/pin_entry_screen.dart';
import 'package:netyemen/features/security/presentation/pin_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../fakes/fake_customer_auth_repository.dart';
import '../../fakes/fake_pin_repository.dart';

/// Minimal stand-in so the PIN gate sees a signed-in user.
class _FakeUser implements User {
  @override
  String get id => 'user-1';

  @override
  noSuchMethod(Invocation invocation) => null;
}

void main() {
  const configuredConfig = AppConfig(
    supabaseUrl: 'http://127.0.0.1:54321',
    supabasePublishableKey: 'test-publishable-key',
  );

  Widget buildScreen(FakeCustomerAuthRepository service) {
    return ProviderScope(
      overrides: [
        customerAuthRepositoryProvider.overrideWithValue(service),
        appConfigProvider.overrideWithValue(configuredConfig),
        currentUserProvider.overrideWithValue(null),
        currentUserRolesProvider.overrideWith((ref) async => const []),
      ],
      child: const MaterialApp(home: LoginScreen()),
    );
  }

  testWidgets('sends a WhatsApp code to the normalized phone and opens OTP', (
    tester,
  ) async {
    final service = FakeCustomerAuthRepository();
    await tester.pumpWidget(buildScreen(service));

    expect(find.byKey(const Key('login-password')), findsNothing);
    await tester.enterText(find.byKey(const Key('login-phone')), '771234567');
    await tester.ensureVisible(find.byKey(const Key('login-whatsapp-otp')));
    await tester.tap(find.byKey(const Key('login-whatsapp-otp')));
    await tester.pumpAndSettle();

    expect(service.phoneOtpRequest, '+967771234567');
    expect(find.byType(OTPScreen), findsOneWidget);
    expect(find.textContaining('واتساب'), findsWidgets);
  });

  testWidgets('a failed WhatsApp send stays on the login screen', (
    tester,
  ) async {
    final service = FakeCustomerAuthRepository()
      ..phoneOtpException = Exception('provider details');
    await tester.pumpWidget(buildScreen(service));

    await tester.enterText(find.byKey(const Key('login-phone')), '771234567');
    await tester.ensureVisible(find.byKey(const Key('login-whatsapp-otp')));
    await tester.tap(find.byKey(const Key('login-whatsapp-otp')));
    await tester.pumpAndSettle();

    expect(find.byType(OTPScreen), findsNothing);
    expect(
      find.text('تعذر إرسال رمز التحقق عبر واتساب حالياً. حاول بعد قليل.'),
      findsOneWidget,
    );
    expect(find.textContaining('provider details'), findsNothing);
  });

  testWidgets('signs in with normalized phone and chosen password', (
    tester,
  ) async {
    final service = FakeCustomerAuthRepository();
    await tester.pumpWidget(buildScreen(service));

    await tester.enterText(find.byKey(const Key('login-phone')), '771234567');
    await tester.ensureVisible(find.byKey(const Key('login-show-password')));
    await tester.tap(find.byKey(const Key('login-show-password')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('login-password')),
      'Pilot1234',
    );
    await tester.ensureVisible(find.byKey(const Key('login-submit')));
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    expect(service.passwordPhone, '+967771234567');
    expect(service.passwordValue, 'Pilot1234');
    expect(find.byType(AppShell), findsOneWidget);
  });

  testWidgets('shows a generic error without leaking auth details', (
    tester,
  ) async {
    final service = FakeCustomerAuthRepository()
      ..passwordException = Exception('internal auth provider details');
    await tester.pumpWidget(buildScreen(service));

    await tester.enterText(find.byKey(const Key('login-phone')), '771234567');
    await tester.ensureVisible(find.byKey(const Key('login-show-password')));
    await tester.tap(find.byKey(const Key('login-show-password')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('login-password')),
      'wrongpass',
    );
    await tester.ensureVisible(find.byKey(const Key('login-submit')));
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    expect(
      find.text('تعذر تسجيل الدخول. تحقق من رقم الهاتف وكلمة المرور.'),
      findsOneWidget,
    );
    expect(find.textContaining('internal auth provider'), findsNothing);
  });

  testWidgets('sign-in on an untrusted device must pass the PIN gate', (
    tester,
  ) async {
    final service = FakeCustomerAuthRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          customerAuthRepositoryProvider.overrideWithValue(service),
          appConfigProvider.overrideWithValue(configuredConfig),
          currentUserProvider.overrideWithValue(_FakeUser()),
          currentUserRolesProvider.overrideWith((ref) async => const []),
          pinRepositoryProvider.overrideWithValue(
            FakePinRepository(status: PinStatus.setAndUntrusted),
          ),
        ],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );

    await tester.enterText(find.byKey(const Key('login-phone')), '771234567');
    await tester.ensureVisible(find.byKey(const Key('login-show-password')));
    await tester.tap(find.byKey(const Key('login-show-password')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('login-password')),
      'Pilot1234',
    );
    await tester.ensureVisible(find.byKey(const Key('login-submit')));
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    expect(find.byType(PinEntryScreen), findsOneWidget);
    expect(find.byType(AppShell), findsNothing);
  });
}
