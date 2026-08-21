import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/providers/app_providers.dart';
import 'package:netyemen/screens/auth/signup_screen.dart';

import '../../fakes/fake_supabase_service.dart';

void main() {
  Widget buildScreen() {
    return ProviderScope(
      overrides: [
        supabaseServiceProvider.overrideWithValue(FakeSupabaseService()),
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

  testWidgets('offline picker records a private approximate location', (
    tester,
  ) async {
    await tester.pumpWidget(buildScreen());
    final picker = find.byKey(const Key('offline-location-picker'));
    await tester.ensureVisible(picker);
    await tester.tapAt(tester.getCenter(picker));
    await tester.pump();

    expect(find.text('لم يتم تحديد الموقع بعد'), findsNothing);
    expect(find.textContaining('الموقع التقريبي:'), findsOneWidget);
    expect(find.textContaining('ليست خريطة عنوان رسمية'), findsOneWidget);
  });
}
