import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/core/config/app_config.dart';
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

    Widget buildScreen({required User? user}) {
      return ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(user),
          appConfigProvider.overrideWithValue(configuredConfig),
          currentUserRolesProvider.overrideWith((ref) async => const []),
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

      expect(find.text('مستخدم مسجل'), findsOneWidget);

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
  });
}
