import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/app/app_shell.dart';
import 'package:netyemen/core/config/app_config.dart';
import 'package:netyemen/providers/app_providers.dart';
import 'package:netyemen/screens/auth/login_screen.dart';

import '../../fakes/fake_supabase_service.dart';

void main() {
  const configuredConfig = AppConfig(
    supabaseUrl: 'http://127.0.0.1:54321',
    supabasePublishableKey: 'test-publishable-key',
  );

  Widget buildScreen(FakeSupabaseService service) {
    return ProviderScope(
      overrides: [
        supabaseServiceProvider.overrideWithValue(service),
        appConfigProvider.overrideWithValue(configuredConfig),
        currentUserProvider.overrideWithValue(null),
        currentUserRolesProvider.overrideWith((ref) async => const []),
      ],
      child: const MaterialApp(home: LoginScreen()),
    );
  }

  testWidgets('signs in with normalized phone and chosen password', (
    tester,
  ) async {
    final service = FakeSupabaseService();
    await tester.pumpWidget(buildScreen(service));

    await tester.enterText(find.byKey(const Key('login-phone')), '771234567');
    await tester.enterText(
      find.byKey(const Key('login-password')),
      'Pilot1234',
    );
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    expect(service.passwordPhone, '+967771234567');
    expect(service.passwordValue, 'Pilot1234');
    expect(find.byType(AppShell), findsOneWidget);
  });

  testWidgets('shows a generic error without leaking auth details', (
    tester,
  ) async {
    final service = FakeSupabaseService()
      ..passwordException = Exception('internal auth provider details');
    await tester.pumpWidget(buildScreen(service));

    await tester.enterText(find.byKey(const Key('login-phone')), '771234567');
    await tester.enterText(
      find.byKey(const Key('login-password')),
      'wrongpass',
    );
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    expect(
      find.text('تعذر تسجيل الدخول. تحقق من رقم الهاتف وكلمة المرور.'),
      findsOneWidget,
    );
    expect(find.textContaining('internal auth provider'), findsNothing);
  });
}
