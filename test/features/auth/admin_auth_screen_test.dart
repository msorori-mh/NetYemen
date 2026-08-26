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

  testWidgets('invalid admin credentials show a precise safe message', (
    tester,
  ) async {
    final repository = FakeAdminAuthRepository(
      signInError: const AuthException(
        'Invalid login credentials',
        statusCode: '400',
        code: 'invalid_credentials',
      ),
    );
    await tester.pumpWidget(
      buildScreen(const AdminEmailSignInScreen(), repository: repository),
    );

    await tester.enterText(
      find.byKey(const Key('admin-email-field')),
      'admin@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('admin-password-field')),
      'wrong-password',
    );
    await tester.tap(find.byKey(const Key('admin-sign-in-button')));
    await tester.pump();

    expect(find.text('البريد أو كلمة المرور غير صحيحة.'), findsOneWidget);
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

  testWidgets('recovery rate limit shows an actionable safe message', (
    tester,
  ) async {
    final repository = FakeAdminAuthRepository(
      recoveryError: const AuthException(
        'Too many emails sent',
        statusCode: '429',
        code: 'over_email_send_rate_limit',
      ),
    );
    await tester.pumpWidget(
      buildScreen(const AdminForgotPasswordScreen(), repository: repository),
    );

    await tester.enterText(
      find.byKey(const Key('admin-recovery-email-field')),
      'admin@example.com',
    );
    await tester.tap(find.byKey(const Key('admin-send-recovery-button')));
    await tester.pump();

    expect(find.textContaining('مرور ساعة'), findsOneWidget);
  });

  testWidgets('default SMTP restriction shows the exact recovery action', (
    tester,
  ) async {
    final repository = FakeAdminAuthRepository(
      recoveryError: const AuthException(
        'Email address not authorized',
        statusCode: '422',
        code: 'email_address_not_authorized',
      ),
    );
    await tester.pumpWidget(
      buildScreen(const AdminForgotPasswordScreen(), repository: repository),
    );

    await tester.enterText(
      find.byKey(const Key('admin-recovery-email-field')),
      'admin@example.com',
    );
    await tester.tap(find.byKey(const Key('admin-send-recovery-button')));
    await tester.pump();

    expect(find.textContaining('أعضاء المؤسسة'), findsOneWidget);
  });

  testWidgets('unknown recovery failure exposes safe debug code and status', (
    tester,
  ) async {
    final repository = FakeAdminAuthRepository(
      recoveryError: const AuthException(
        'Unexpected recovery failure',
        statusCode: '500',
        code: 'unexpected_failure',
      ),
    );
    await tester.pumpWidget(
      buildScreen(const AdminForgotPasswordScreen(), repository: repository),
    );

    await tester.enterText(
      find.byKey(const Key('admin-recovery-email-field')),
      'admin@example.com',
    );
    await tester.tap(find.byKey(const Key('admin-send-recovery-button')));
    await tester.pump();

    expect(find.textContaining('code=unexpected_failure'), findsOneWidget);
    expect(find.textContaining('status=500'), findsOneWidget);
  });

  testWidgets('recovery redirect rejection identifies configuration gate', (
    tester,
  ) async {
    final repository = FakeAdminAuthRepository(
      recoveryError: const AuthException('Redirect URL is not allowed'),
    );
    await tester.pumpWidget(
      buildScreen(const AdminForgotPasswordScreen(), repository: repository),
    );

    await tester.enterText(
      find.byKey(const Key('admin-recovery-email-field')),
      'admin@example.com',
    );
    await tester.tap(find.byKey(const Key('admin-send-recovery-button')));
    await tester.pump();

    expect(find.textContaining('Redirect URLs'), findsOneWidget);
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
  final Object? signInError;
  final Object? recoveryError;
  String? signInEmail;
  String? signInPassword;
  String? recoveryEmail;
  String? recoveryRedirectUrl;
  String? updatedPassword;
  bool didSignOut = false;

  FakeAdminAuthRepository({this.signInError, this.recoveryError});

  @override
  Stream<AdminAuthEvent> get events => const Stream.empty();

  @override
  Future<void> signIn({required String email, required String password}) async {
    signInEmail = email;
    signInPassword = password;
    if (signInError != null) throw signInError!;
  }

  @override
  Future<void> requestPasswordRecovery({
    required String email,
    required String redirectUrl,
  }) async {
    recoveryEmail = email;
    recoveryRedirectUrl = redirectUrl;
    if (recoveryError != null) throw recoveryError!;
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
