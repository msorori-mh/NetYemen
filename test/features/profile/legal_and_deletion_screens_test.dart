import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/core/config/app_config.dart';
import 'package:netyemen/features/notifications/data/fake_notification_repository.dart';
import 'package:netyemen/features/notifications/presentation/fcm_token_service.dart';
import 'package:netyemen/features/profile/data/account_deletion_repository.dart';
import 'package:netyemen/features/profile/presentation/legal_and_deletion_screens.dart';
import 'package:netyemen/core/config/app_config_provider.dart';
import 'package:netyemen/features/auth/presentation/customer_auth_providers.dart';

import '../../fakes/fake_customer_auth_repository.dart';

void main() {
  const config = AppConfig(
    supabaseUrl: 'https://example.supabase.co',
    supabasePublishableKey: 'test-key',
    privacyPolicyUrl: 'https://legal.example.com/privacy',
    accountDeletionUrl: 'https://legal.example.com/delete-account',
  );

  testWidgets('public privacy link opens only the configured HTTPS URL', (
    tester,
  ) async {
    Uri? opened;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(config),
          legalUrlLauncherProvider.overrideWithValue((uri) async {
            opened = uri;
            return true;
          }),
        ],
        child: const MaterialApp(home: PrivacyPolicyScreen()),
      ),
    );

    await tester.tap(find.byKey(const Key('public-privacy-policy-link')));
    await tester.pump();

    expect(opened, Uri.parse('https://legal.example.com/privacy'));
  });

  testWidgets('legal link failure is contained with a safe message', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(config),
          legalUrlLauncherProvider.overrideWithValue((_) async {
            throw Exception('LAUNCH_FAILED');
          }),
        ],
        child: const MaterialApp(home: PrivacyPolicyScreen()),
      ),
    );

    await tester.tap(find.byKey(const Key('public-privacy-policy-link')));
    await tester.pump();

    expect(find.text('تعذر فتح الرابط الآمن.'), findsOneWidget);
  });

  testWidgets('account deletion stays disabled until both confirmations', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(config),
          accountDeletionRepositoryProvider.overrideWithValue(
            _FakeAccountDeletionRepository(),
          ),
        ],
        child: const MaterialApp(home: AccountDeletionScreen()),
      ),
    );

    FilledButton button() => tester.widget<FilledButton>(
          find.byKey(const Key('request-account-deletion-button')),
        );

    expect(button().onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('account-deletion-confirmation-field')),
      'حذف حسابي',
    );
    await tester.pump();
    expect(button().onPressed, isNull);

    await tester.tap(
      find.byKey(const Key('account-deletion-understood-checkbox')),
    );
    await tester.pump();
    expect(button().onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('request-account-deletion-button')));
    await tester.pumpAndSettle();
    expect(find.text('تأكيد طلب حذف الحساب'), findsOneWidget);

    await tester.tap(find.text('تراجع'));
    await tester.pumpAndSettle();
    expect(find.text('تأكيد طلب حذف الحساب'), findsNothing);
  });

  testWidgets('successful deletion uses the server receipt and signs out', (
    tester,
  ) async {
    final repository = _FakeAccountDeletionRepository();
    final authService = FakeCustomerAuthRepository();
    final fcmService = _RecordingFcmTokenService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(config),
          accountDeletionRepositoryProvider.overrideWithValue(repository),
          customerAuthRepositoryProvider.overrideWithValue(authService),
          fcmTokenServiceProvider.overrideWithValue(fcmService),
        ],
        child: const MaterialApp(home: AccountDeletionScreen()),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('account-deletion-reason-field')),
      'لم أعد أحتاج الحساب',
    );
    await _confirmDeletion(tester);

    expect(repository.calls, 1);
    expect(repository.reason, 'لم أعد أحتاج الحساب');
    expect(fcmService.deactivateCalls, 1);
    expect(authService.signOutCalled, isTrue);
    expect(find.textContaining('21/9/2026'), findsOneWidget);
    expect(find.byKey(const Key('account-deletion-error')), findsNothing);
  });

  testWidgets(
    'sign-out failure does not relabel a confirmed request as failed',
    (tester) async {
      final repository = _FakeAccountDeletionRepository();
      final authService = FakeCustomerAuthRepository()
        ..signOutException = Exception('SIGN_OUT_FAILED');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appConfigProvider.overrideWithValue(config),
            accountDeletionRepositoryProvider.overrideWithValue(repository),
            customerAuthRepositoryProvider.overrideWithValue(authService),
            fcmTokenServiceProvider.overrideWithValue(
              _RecordingFcmTokenService(),
            ),
          ],
          child: const MaterialApp(home: AccountDeletionScreen()),
        ),
      );

      await _confirmDeletion(tester);

      expect(repository.calls, 1);
      expect(find.byKey(const Key('account-deletion-error')), findsNothing);
      expect(find.textContaining('تعذر تسجيل الخروج تلقائيًا'), findsOneWidget);
    },
  );
}

class _FakeAccountDeletionRepository implements AccountDeletionRepository {
  int calls = 0;
  String? reason;

  @override
  Future<AccountDeletionReceipt> requestDeletion({String? reason}) async {
    calls++;
    this.reason = reason;
    return AccountDeletionReceipt(
      requestId: 'a6180000-0000-4000-8000-000000000010',
      scheduledFor: DateTime.utc(2026, 9, 21, 12),
      idempotent: false,
    );
  }
}

class _RecordingFcmTokenService extends FcmTokenService {
  _RecordingFcmTokenService() : super(repository: FakeNotificationRepository());

  int deactivateCalls = 0;

  @override
  Future<void> stop({bool deactivateToken = false}) async {
    if (deactivateToken) deactivateCalls++;
  }
}

Future<void> _confirmDeletion(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('account-deletion-confirmation-field')),
    'حذف حسابي',
  );
  await tester.tap(
    find.byKey(const Key('account-deletion-understood-checkbox')),
  );
  await tester.pump();
  await tester.tap(find.byKey(const Key('request-account-deletion-button')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('confirm-account-deletion-button')));
  await tester.pumpAndSettle();
}
