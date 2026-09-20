import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/app/app_shell.dart';
import 'package:netyemen/core/config/app_config.dart';
import 'package:netyemen/core/config/app_config_provider.dart';
import 'package:netyemen/features/auth/presentation/customer_session_providers.dart';

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
    final navigationBarFinder = find.byType(NavigationBar);
    expect(
      find.descendant(
        of: navigationBarFinder,
        matching: find.text('الرئيسية'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: navigationBarFinder,
        matching: find.text('الشبكات'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: navigationBarFinder,
        matching: find.text('المحفظة'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: navigationBarFinder,
        matching: find.text('المشتريات'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: navigationBarFinder,
        matching: find.text('الحساب'),
      ),
      findsOneWidget,
    );
    expect(find.text('الإدارة'), findsNothing);
    expect(find.text('الإدارة والمالية'), findsNothing);

    await tester.tap(find.byKey(const Key('home-open-networks')));
    await tester.pump();

    final navigationBar = tester.widget<NavigationBar>(
      navigationBarFinder,
    );
    expect(navigationBar.selectedIndex, 1);
  });
}
