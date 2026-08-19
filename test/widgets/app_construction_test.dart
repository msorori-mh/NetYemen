import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netyemen/utils/app_theme.dart';

void main() {
  group('Basic Application Construction Test', () {
    testWidgets('App theme and basic widget tree construct successfully', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                seedColor: AppTheme.primary,
                brightness: Brightness.light,
              ),
              scaffoldBackgroundColor: AppTheme.background,
            ),
            home: const Scaffold(
              body: Center(child: Text('NetYemen Baseline Test')),
            ),
          ),
        ),
      );

      expect(find.text('NetYemen Baseline Test'), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget);
    });
  });
}
