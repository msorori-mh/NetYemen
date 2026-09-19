import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/app/app_shell.dart';
import 'package:netyemen/core/config/app_config.dart';
import 'package:netyemen/providers/app_providers.dart';

void main() {
  testWidgets('customer shell always exposes only customer destinations', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(AppConfig.demo),
          currentUserProvider.overrideWithValue(null),
          currentUserRolesProvider.overrideWith(
            (ref) async => const [
              'platform_admin',
              'finance_officer',
              'network_owner',
            ],
          ),
        ],
        child: const MaterialApp(home: AppShell()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationDestination), findsNWidgets(5));
    expect(find.text('الرئيسية'), findsOneWidget);
    expect(find.text('الشبكات'), findsOneWidget);
    expect(find.text('المحفظة'), findsOneWidget);
    expect(find.text('المشتريات'), findsOneWidget);
    expect(find.text('الحساب'), findsOneWidget);
    expect(find.text('الإدارة'), findsNothing);
    expect(find.text('الإدارة والمالية'), findsNothing);
  });
}
