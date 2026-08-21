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
