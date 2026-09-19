import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/core/config/app_config.dart';
import 'package:netyemen/features/profile/domain/customer_profile.dart';
import 'package:netyemen/features/profile/presentation/profile_screen.dart';
import 'package:netyemen/features/profile/presentation/legal_and_deletion_screens.dart';
import 'package:netyemen/providers/app_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('ProfileScreen', () {
    const configuredConfig = AppConfig(
      supabaseUrl: 'http://127.0.0.1:54321',
      supabasePublishableKey: 'test-publishable-key',
    );

    Widget buildScreen({
      required User? user,
      AppConfig config = configuredConfig,
      List<String> roles = const [],
      CustomerProfile? profile,
    }) {
      return ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(user),
          appConfigProvider.overrideWithValue(config),
          currentUserRolesProvider.overrideWith((ref) async => roles),
          userProfileProvider.overrideWith((ref) async {
            if (profile != null) return profile;
            if (user == null) return null;
            return CustomerProfile(
              id: user.id,
              fullName: 'أحمد محمد',
              governorate: 'مأرب',
              city: 'مدينة مأرب',
            );
          }),
        ],
        child: const MaterialApp(home: ProfileScreen()),
      );
    }

    testWidgets('shows sign-out button for authenticated user', (tester) async {
      await tester.pumpWidget(
        buildScreen(
          user: User(
            id: 'a1a1a1a1-a1a1-4a1a-a1a1-a1a1a1a1a1a1',
            appMetadata: {},
            userMetadata: {},
            aud: 'authenticated',
            createdAt: DateTime.now().toIso8601String(),
          ),
        ),
      );

      await tester.pump();
      expect(find.text('أحمد محمد'), findsOneWidget);
      expect(find.text('مأرب — مدينة مأرب'), findsOneWidget);
      expect(find.byKey(const Key('profile-edit-entry')), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('إعدادات الإشعارات'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('إعدادات الإشعارات'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('تسجيل الخروج'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(OutlinedButton, 'تسجيل الخروج'),
        findsOneWidget,
      );
      expect(find.widgetWithText(ElevatedButton, 'تسجيل الدخول'), findsNothing);

      await tester.scrollUntilVisible(
        find.byKey(const Key('account-deletion-entry')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('account-deletion-entry')), findsOneWidget);
    });

    testWidgets('shows sign-in button for unauthenticated user', (
      tester,
    ) async {
      await tester.pumpWidget(buildScreen(user: null));

      expect(find.text('غير مسجل'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('تسجيل الدخول'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('تسجيل الدخول'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'تسجيل الخروج'), findsNothing);
      expect(find.byKey(const Key('account-deletion-entry')), findsNothing);
    });

    testWidgets('inactive account is visible and profile editing is disabled', (
      tester,
    ) async {
      final user = User(
        id: 'a1a1a1a1-a1a1-4a1a-a1a1-a1a1a1a1a1a1',
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
      );
      await tester.pumpWidget(
        buildScreen(
          user: user,
          profile: CustomerProfile(
            id: user.id,
            fullName: 'حساب موقوف',
            governorate: 'عدن',
            city: 'كريتر',
            isActive: false,
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('profile-inactive-warning')), findsOneWidget);
      final editEntry = tester.widget<ListTile>(
        find.byKey(const Key('profile-edit-entry')),
      );
      expect(editEntry.onTap, isNull);
    });

    testWidgets('privacy entry opens the in-app policy', (tester) async {
      await tester.pumpWidget(buildScreen(user: null));

      await tester.scrollUntilVisible(
        find.text('الخصوصية'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('الخصوصية'));
      await tester.pumpAndSettle();

      expect(find.byType(PrivacyPolicyScreen), findsOneWidget);
      expect(find.text('خصوصيتك في واصل نت'), findsOneWidget);
    });

    testWidgets('does not expose privileged dashboards to customer users', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildScreen(
          user: null,
          config: AppConfig.demo,
          roles: const ['platform_admin', 'network_owner'],
        ),
      );

      await tester.dragUntilVisible(
        find.text('عن التطبيق'),
        find.byType(Scrollable).first,
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();

      expect(find.text('عمليات الشبكة'), findsNothing);
      expect(find.text('لوحة الإدارة'), findsNothing);
    });
  });
}
