import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/core/config/app_config.dart';
import 'package:netyemen/features/profile/data/account_deletion_repository.dart';
import 'package:netyemen/features/profile/presentation/legal_and_deletion_screens.dart';
import 'package:netyemen/providers/app_providers.dart';

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
}

class _FakeAccountDeletionRepository implements AccountDeletionRepository {
  @override
  Future<AccountDeletionReceipt> requestDeletion({String? reason}) async {
    return AccountDeletionReceipt(
      requestId: 'a6180000-0000-4000-8000-000000000010',
      scheduledFor: DateTime.utc(2026, 9, 21),
      idempotent: false,
    );
  }
}
