import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/app/app_shell.dart';
import 'package:netyemen/core/config/app_config.dart';
import 'package:netyemen/core/config/app_config_provider.dart';
import 'package:netyemen/features/auth/presentation/customer_auth_providers.dart';
import 'package:netyemen/features/auth/presentation/customer_session_providers.dart';

import 'package:netyemen/features/auth/presentation/otp_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../fakes/fake_customer_auth_repository.dart';

void main() {
  group('OTPScreen', () {
    const configuredConfig = AppConfig(
      supabaseUrl: 'http://127.0.0.1:54321',
      supabasePublishableKey: 'test-publishable-key',
    );

    Widget buildScreen(
        {required FakeCustomerAuthRepository service, User? user}) {
      return ProviderScope(
        overrides: [
          customerAuthRepositoryProvider.overrideWithValue(service),
          currentUserProvider.overrideWithValue(user),
          appConfigProvider.overrideWithValue(configuredConfig),
        ],
        child: const MaterialApp(home: OTPScreen(phone: '+967770000000')),
      );
    }

    testWidgets(
      'successful OTP verification navigates to AppShell without legacy users table call',
      (tester) async {
        final service = FakeCustomerAuthRepository()
          ..otpResult = User(
            id: 'a1a1a1a1-a1a1-4a1a-a1a1-a1a1a1a1a1a1',
            appMetadata: {},
            userMetadata: {},
            aud: 'authenticated',
            createdAt: DateTime.now().toIso8601String(),
          );

        await tester.pumpWidget(buildScreen(service: service));

        await tester.enterText(find.byType(TextField), '123456');
        await tester.tap(find.byType(ElevatedButton));
        await tester.pumpAndSettle();

        expect(find.byType(AppShell), findsOneWidget);
        expect(service.otpPhone, '+967770000000');
        expect(service.otpValue, '123456');
      },
    );

    testWidgets('invalid OTP shows Arabic error', (tester) async {
      final service = FakeCustomerAuthRepository()
        ..otpException = Exception('invalid token');

      await tester.pumpWidget(buildScreen(service: service));

      await tester.enterText(find.byType(TextField), '000000');
      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();

      expect(find.text('رمز التحقق غير صحيح'), findsOneWidget);
    });

    testWidgets('resend is locked for the cooldown, then sends a new code', (
      tester,
    ) async {
      final service = FakeCustomerAuthRepository();
      await tester.pumpWidget(buildScreen(service: service));

      TextButton resendButton() =>
          tester.widget<TextButton>(find.byKey(const Key('otp-resend')));

      expect(resendButton().onPressed, isNull);
      expect(find.textContaining('60'), findsOneWidget);
      expect(service.phoneOtpRequest, isNull);

      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      expect(resendButton().onPressed, isNull);

      await tester.pump(const Duration(seconds: 31));
      await tester.pump();
      expect(resendButton().onPressed, isNotNull);
      expect(find.text('إعادة إرسال الرمز'), findsOneWidget);

      await tester.tap(find.byKey(const Key('otp-resend')));
      await tester.pump();
      await tester.pump();

      expect(service.phoneOtpRequest, '+967770000000');
      expect(
        resendButton().onPressed,
        isNull,
        reason: 'a new cooldown starts after each resend',
      );
    });

    testWidgets('accepts a code typed with Arabic-Indic digits', (
      tester,
    ) async {
      final service = FakeCustomerAuthRepository()
        ..otpException = Exception('invalid token');

      await tester.pumpWidget(buildScreen(service: service));

      await tester.enterText(find.byType(TextField), '١٢٣٤٥٦');
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      await tester.pump();

      expect(service.otpValue, '123456');
    });
  });
}
