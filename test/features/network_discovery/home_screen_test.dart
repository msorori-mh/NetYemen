import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/core/config/app_config.dart';
import 'package:netyemen/features/network_discovery/presentation/home_screen.dart';
import 'package:netyemen/providers/app_providers.dart';

void main() {
  testWidgets('home summarizes the main customer tasks in demo mode', (
    tester,
  ) async {
    int? selectedDestination;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(AppConfig.demo),
          currentUserProvider.overrideWithValue(null),
        ],
        child: MaterialApp(
          home: HomeScreen(
            onSelectDestination: (index) => selectedDestination = index,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('مرحبًا بك في واصل نت'), findsOneWidget);
    expect(find.text('5000 YER'), findsOneWidget);
    expect(find.text('شبكات مقترحة'), findsOneWidget);
    expect(find.text('شبكة يمن نت'), findsOneWidget);
    expect(find.text('شبكة عدن للاتصالات'), findsOneWidget);
    expect(find.text('شبكة تعز السريعة'), findsOneWidget);

    await tester.tap(find.byKey(const Key('home-open-networks')));
    expect(selectedDestination, 1);

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(
      find.text('لا توجد مشتريات بعد. ابدأ باختيار شبكة وباقة.'),
      findsOneWidget,
    );
  });
}
