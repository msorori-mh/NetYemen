import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/core/config/app_config.dart';
import 'package:netyemen/features/auth/data/admin_auth_repository.dart';
import 'package:netyemen/features/auth/presentation/admin_auth_providers.dart';
import 'package:netyemen/features/auth/presentation/admin_auth_screen.dart';
import 'package:netyemen/providers/app_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const configuredConfig = AppConfig(
    supabaseUrl: 'https://example.supabase.co',
    supabasePublishableKey: 'test-publishable-key',
    adminPasswordRecoveryRedirectUrl: 'https://admin.example.com',
  );

  Widget buildScreen(
    Widget child, {
    required FakeAdminAuthRepository repository,
    User? user,
    AppConfig config = configuredConfig,
  }) {
    return ProviderScope(
      overrides: [
        adminAuthRepositoryProvider.overrideWithValue(repository),
        appConfigProvider.overrideWithValue(config),
        currentUserProvider.overrideWithValue(user),
      ],
      child: MaterialApp(home: child),
    );
  }

  testWidgets('admin signs in with email and password', (tester) async {
    final repository = FakeAdminAuthRepository();
    await tester.pumpWidget(
      buildScreen(const AdminEmailSignInScreen(), repository: repository),
    );

    await tester.enterText(
      find.byKey(const Key('admin-email-field')),
      'admin@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('admin-password-field')),
      'correct-horse-battery-staple',
    );
    await tester.tap(find.byKey(const Key('admin-sign-in-button')));
    await tester.pump();

    expect(repository.signInEmail, 'admin@example.com');
    expect(repository.signInPassword, 'correct-horse-battery-staple');
  });

  testWidgets('recovery request uses configured admin origin', (tester) async {
    final repository = FakeAdminAuthRepository();
    await tester.pumpWidget(
      buildScreen(const AdminForgotPasswordScreen(), repository: repository),
    );

    await tester.enterText(
      find.byKey(const Key('admin-recovery-email-field')),
      'admin@example.com',
    );
    await tester.tap(find.byKey(const Key('admin-send-recovery-button')));
    await tester.pump();

    expect(repository.recoveryEmail, 'admin@example.com');
    expect(
      repository.recoveryRedirectUrl,
      'https://admin.example.com?mode=recovery',
    );
    expect(find.textContaining('إذا كان الحساب موجودًا'), findsOneWidget);
  });

  testWidgets('recovery request fails closed without valid redirect', (
    tester,
  ) async {
    final repository = FakeAdminAuthRepository();
    await tester.pumpWidget(
      buildScreen(
        const AdminForgotPasswordScreen(),
        repository: repository,
        config: const AppConfig(
          supabaseUrl: 'https://example.supabase.co',
          supabasePublishableKey: 'test-publishable-key',
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('admin-recovery-email-field')),
      'admin@example.com',
    );
    await tester.tap(find.byKey(const Key('admin-send-recovery-button')));
    await tester.pump();

    expect(repository.recoveryEmail, isNull);
    expect(
      find.text('إعداد رابط استعادة لوحة الإدارة غير مكتمل.'),
      findsOneWidget,
    );
  });

  testWidgets('new password must match before update', (tester) async {
    final repository = FakeAdminAuthRepository();
    await tester.pumpWidget(
      buildScreen(
        AdminPasswordRecoveryScreen(onCompleted: () {}),
        repository: repository,
        user: testUser(),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('admin-new-password-field')),
      'new-password-123',
    );
    await tester.enterText(
      find.byKey(const Key('admin-confirm-password-field')),
      'different-password',
    );
    await tester.tap(find.byKey(const Key('admin-update-password-button')));
    await tester.pump();

    expect(find.text('كلمتا المرور غير متطابقتين'), findsOneWidget);
    expect(repository.updatedPassword, isNull);
  });

  testWidgets('valid recovery updates password and signs session out', (
    tester,
  ) async {
    final repository = FakeAdminAuthRepository();
    var completed = false;
    await tester.pumpWidget(
      buildScreen(
        AdminPasswordRecoveryScreen(onCompleted: () => completed = true),
        repository: repository,
        user: testUser(),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('admin-new-password-field')),
      'new-password-123',
    );
    await tester.enterText(
      find.byKey(const Key('admin-confirm-password-field')),
      'new-password-123',
    );
    await tester.tap(find.byKey(const Key('admin-update-password-button')));
    await tester.pump();

    expect(repository.updatedPassword, 'new-password-123');
    expect(repository.didSignOut, isTrue);
    expect(completed, isTrue);
  });
}

User testUser() => User(
  id: 'a1a1a1a1-a1a1-4a1a-a1a1-a1a1a1a1a1a1',
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: DateTime.now().toIso8601String(),
);

class FakeAdminAuthRepository implements AdminAuthRepository {
  String? signInEmail;
  String? signInPassword;
  String? recoveryEmail;
  String? recoveryRedirectUrl;
  String? updatedPassword;
  bool didSignOut = false;

  @override
  Stream<AdminAuthEvent> get events => const Stream.empty();

  @override
  Future<void> signIn({required String email, required String password}) async {
    signInEmail = email;
    signInPassword = password;
  }

  @override
  Future<void> requestPasswordRecovery({
    required String email,
    required String redirectUrl,
  }) async {
    recoveryEmail = email;
    recoveryRedirectUrl = redirectUrl;
  }

  @override
  Future<void> updatePassword(String password) async {
    updatedPassword = password;
  }

  @override
  Future<void> signOut() async {
    didSignOut = true;
  }
}
