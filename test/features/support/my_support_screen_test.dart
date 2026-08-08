import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/features/support/data/fake_support_repository.dart';
import 'package:netyemen/features/support/presentation/support_providers.dart';
import 'package:netyemen/features/support/presentation/support_screens.dart';

void main() {
  testWidgets('Arabic empty state and create action render', (tester) async {
    await tester.pumpWidget(ProviderScope(
        overrides: [
          supportRepositoryProvider.overrideWithValue(FakeSupportRepository())
        ],
        child: const MaterialApp(
            home: Directionality(
                textDirection: TextDirection.rtl, child: MySupportScreen()))));
    await tester.pumpAndSettle();
    expect(find.text('دعمي'), findsOneWidget);
    expect(find.text('لا توجد تذاكر دعم بعد'), findsOneWidget);
    expect(find.text('تذكرة جديدة'), findsOneWidget);
  });
}
