import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/app/app_shell.dart';
import 'package:netyemen/core/config/app_config.dart';
import 'package:netyemen/features/auth/domain/customer_auth.dart';
import 'package:netyemen/providers/app_providers.dart';
import 'package:netyemen/screens/auth/signup_screen.dart';

import '../../fakes/fake_supabase_service.dart';

void main() {
  const configuredConfig = AppConfig(
    supabaseUrl: 'http://127.0.0.1:54321',
    supabasePublishableKey: 'test-publishable-key',
  );

  Widget buildScreen([FakeSupabaseService? service]) {
    return ProviderScope(
      overrides: [
        supabaseServiceProvider.overrideWithValue(
          service ?? FakeSupabaseService(),
        ),
        appConfigProvider.overrideWithValue(configuredConfig),
        currentUserProvider.overrideWithValue(null),
        currentUserRolesProvider.overrideWith((ref) async => const []),
      ],
      child: const MaterialApp(home: SignupScreen()),
    );
  }

  testWidgets('explains the temporary tester and owner-review boundaries', (
    tester,
  ) async {
    await tester.pumpWidget(buildScreen());

    expect(find.textContaining('مسار مؤقت للمختبرين'), findsOneWidget);
    expect(find.text('نوع الحساب المطلوب'), findsOneWidget);

    await tester.tap(find.byKey(const Key('signup-account-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('صاحب شبكة').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('سيُنشأ الحساب كزبون أولاً'), findsOneWidget);
  });

  testWidgets('submits the complete customer signup journey and enters app', (
    tester,
  ) async {
    final service = FakeSupabaseService();
    await tester.pumpWidget(buildScreen(service));

    await tester.enterText(
      find.byKey(const Key('signup-full-name')),
      'مختبر الرحلة الكاملة',
    );
    await tester.enterText(
      find.byKey(const Key('signup-phone')),
      '771234567',
    );
    await tester.enterText(
      find.byKey(const Key('signup-password')),
      'Pilot1234',
    );
    await tester.enterText(
      find.byKey(const Key('signup-confirm-password')),
      'Pilot1234',
    );

    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.byKey(const Key('offline-location-picker')),
      300,
      scrollable: scrollable,
    );
    await tester.tap(find.byKey(const Key('offline-location-picker')));
    await tester.scrollUntilVisible(
      find.byKey(const Key('signup-location-consent')),
      200,
      scrollable: scrollable,
    );
    await tester.tap(find.byKey(const Key('signup-location-consent')));

    await tester.scrollUntilVisible(
      find.byKey(const Key('signup-invite')),
      300,
      scrollable: scrollable,
    );
    await tester.enterText(
      find.byKey(const Key('signup-invite')),
      'TEST-INVITE-1234',
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('signup-submit')),
      300,
      scrollable: scrollable,
    );
    await tester.tap(find.byKey(const Key('signup-submit')));
    await tester.pumpAndSettle();

    final registration = service.registration;
    expect(registration, isNotNull);
    expect(registration!.toFunctionBody()['phone'], '+967771234567');
    expect(registration.requestedAccountType, RequestedAccountType.customer);
    expect(registration.password, 'Pilot1234');
    expect(registration.inviteCode, 'TEST-INVITE-1234');
    expect(find.text('تم إنشاء الحساب الاختباري'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'متابعة'));
    await tester.pumpAndSettle();
    expect(find.byType(AppShell), findsOneWidget);
  });

  testWidgets('offline picker records a private approximate location', (
    tester,
  ) async {
    PilotLocation? selectedLocation;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: StatefulBuilder(
                builder: (context, setState) {
                  return OfflinePilotLocationPicker(
                    value: selectedLocation,
                    onChanged: (value) {
                      setState(() => selectedLocation = value);
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    final picker = find.byKey(const Key('offline-location-picker'));
    expect(picker, findsOneWidget);
    await tester.tap(picker);
    await tester.pump();

    expect(selectedLocation, isNotNull);
    expect(find.text('لم يتم تحديد الموقع بعد'), findsNothing);
    expect(find.textContaining('الموقع التقريبي:'), findsOneWidget);
    expect(find.textContaining('ليست خريطة عنوان رسمية'), findsOneWidget);
  });
}
