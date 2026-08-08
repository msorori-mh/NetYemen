import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/core/config/app_config.dart';
import 'package:netyemen/features/auth/presentation/auth_required_gate.dart';
import 'package:netyemen/providers/app_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('AuthRequiredGate', () {
    const configuredConfig = AppConfig(
      supabaseUrl: 'http://127.0.0.1:54321',
      supabasePublishableKey: 'test-publishable-key',
    );

    Widget buildGate({
      required User? user,
      required AppConfig config,
      required Widget child,
    }) {
      return ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(user),
          appConfigProvider.overrideWithValue(config),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: AuthRequiredGate(child: child),
          ),
        ),
      );
    }

    testWidgets('shows child when a user is signed in', (tester) async {
      await tester.pumpWidget(
        buildGate(
          user: User(
            id: 'a1a1a1a1-a1a1-4a1a-a1a1-a1a1a1a1a1a1',
            appMetadata: {},
            userMetadata: {},
            aud: 'authenticated',
            createdAt: DateTime.now().toIso8601String(),
          ),
          config: configuredConfig,
          child: const Text('PROTECTED_CONTENT'),
        ),
      );

      expect(find.text('PROTECTED_CONTENT'), findsOneWidget);
      expect(find.text('تسجيل الدخول مطلوب'), findsNothing);
    });

    testWidgets('shows Arabic auth-required state when user is null', (tester) async {
      await tester.pumpWidget(
        buildGate(
          user: null,
          config: configuredConfig,
          child: const Text('PROTECTED_CONTENT'),
        ),
      );

      expect(find.text('PROTECTED_CONTENT'), findsNothing);
      expect(find.text('تسجيل الدخول مطلوب'), findsOneWidget);
      expect(find.text('يجب تسجيل الدخول لعرض هذا القسم.'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'تسجيل الدخول'), findsOneWidget);
    });

    testWidgets('bypasses gate in demo/unconfigured mode', (tester) async {
      await tester.pumpWidget(
        buildGate(
          user: null,
          config: AppConfig.demo,
          child: const Text('PROTECTED_CONTENT'),
        ),
      );

      expect(find.text('PROTECTED_CONTENT'), findsOneWidget);
      expect(find.text('تسجيل الدخول مطلوب'), findsNothing);
    });
  });
}
