import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/core/config/app_config.dart';
import 'package:netyemen/features/admin/data/fake_admin_repository.dart';
import 'package:netyemen/features/admin/presentation/admin_providers.dart';
import 'package:netyemen/features/admin/presentation/admin_users_screen.dart';
import 'package:netyemen/providers/app_providers.dart';

void main() {
  testWidgets('admin replaces platform roles atomically from user menu', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(AppConfig.demo),
          adminRepositoryProvider.overrideWithValue(FakeAdminRepository()),
          currentUserRolesProvider.overrideWith(
            (_) => const ['platform_admin'],
          ),
        ],
        child: const MaterialApp(home: AdminUsersScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('مدير المنصة'), findsWidgets);

    await tester.tap(find.byTooltip('إدارة المستخدم').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('إدارة الأدوار الإدارية'));
    await tester.pumpAndSettle();

    expect(find.textContaining('الأدوار الإدارية'), findsWidgets);
    await tester.tap(find.widgetWithText(CheckboxListTile, 'مسؤول مالي'));
    await tester.tap(find.widgetWithText(FilledButton, 'حفظ'));
    await tester.pumpAndSettle();

    expect(find.text('تم تحديث الأدوار الإدارية'), findsOneWidget);
    expect(find.text('مسؤول مالي'), findsWidgets);
  });

  testWidgets('account status mutation requires confirmation', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(AppConfig.demo),
          adminRepositoryProvider.overrideWithValue(FakeAdminRepository()),
          currentUserRolesProvider.overrideWith(
            (_) => const ['platform_admin'],
          ),
        ],
        child: const MaterialApp(home: AdminUsersScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('إدارة المستخدم').at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تعليق الحساب'));
    await tester.pumpAndSettle();

    expect(find.text('تعليق الحساب'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'تأكيد'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'إلغاء'));
    await tester.pumpAndSettle();

    expect(find.text('تم تعليق الحساب'), findsNothing);
  });
}
