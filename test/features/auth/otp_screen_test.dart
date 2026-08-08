import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/app/app_shell.dart';
import 'package:netyemen/core/config/app_config.dart';
import 'package:netyemen/providers/app_providers.dart';
import 'package:netyemen/screens/auth/otp_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../fakes/fake_supabase_service.dart';

void main() {
  group('OTPScreen', () {
    const configuredConfig = AppConfig(
      supabaseUrl: 'http://127.0.0.1:54321',
      supabasePublishableKey: 'test-publishable-key',
    );

    Widget buildScreen({
      required FakeSupabaseService service,
      User? user,
    }) {
      return ProviderScope(
        overrides: [
          supabaseServiceProvider.overrideWithValue(service),
          currentUserProvider.overrideWithValue(user),
          appConfigProvider.overrideWithValue(configuredConfig),
        ],
        child: const MaterialApp(
          home: OTPScreen(phone: '+967770000000'),
        ),
      );
    }

    testWidgets('successful OTP verification navigates to AppShell without legacy users table call',
        (tester) async {
      final service = FakeSupabaseService()
        ..verifyResult = User(
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
      expect(service.verifyPhone, '+967770000000');
      expect(service.verifyOtp, '123456');
    });

    testWidgets('invalid OTP shows Arabic error', (tester) async {
      final service = FakeSupabaseService()
        ..verifyException = Exception('invalid token');

      await tester.pumpWidget(buildScreen(service: service));

      await tester.enterText(find.byType(TextField), '000000');
      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();

      expect(find.text('رمز التحقق غير صحيح'), findsOneWidget);
    });
  });
}
