import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/core/config/app_config.dart';
import 'package:netyemen/core/config/app_config_provider.dart';
import 'package:netyemen/features/auth/presentation/customer_session_providers.dart';
import 'package:netyemen/features/notifications/presentation/notification_providers.dart';
import 'package:netyemen/features/purchase/presentation/purchase_providers.dart';
import 'package:netyemen/features/support/presentation/support_providers.dart';
import 'package:netyemen/features/wallet/presentation/wallet_providers.dart';
import 'package:netyemen/features/wasel_one/presentation/wasel_one_providers.dart';

void main() {
  late StateController<String?> signedInUser;
  late ProviderContainer container;

  setUp(() {
    final userIdState = StateProvider<String?>((ref) => 'user-a');
    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(AppConfig.demo),
        currentUserIdProvider.overrideWith((ref) => ref.watch(userIdState)),
      ],
    );
    signedInUser = container.read(userIdState.notifier);
  });

  tearDown(() => container.dispose());

  List<Object> userScopedRepositories() => [
        container.read(walletRepositoryProvider),
        container.read(purchaseRepositoryProvider),
        container.read(notificationRepositoryProvider),
        container.read(waselOneRepositoryProvider),
        container.read(supportRepositoryProvider),
      ];

  test('switching accounts rebuilds every user-scoped repository', () {
    final before = userScopedRepositories();

    signedInUser.state = 'user-b';
    final after = userScopedRepositories();

    for (var i = 0; i < before.length; i++) {
      expect(identical(before[i], after[i]), isFalse, reason: 'index $i');
    }
  });

  test('signing out rebuilds user-scoped repositories', () {
    final before = userScopedRepositories();

    signedInUser.state = null;
    final after = userScopedRepositories();

    for (var i = 0; i < before.length; i++) {
      expect(identical(before[i], after[i]), isFalse, reason: 'index $i');
    }
  });

  test('a token refresh for the same user keeps cached repositories', () {
    final before = userScopedRepositories();

    signedInUser.state = 'user-a';
    final after = userScopedRepositories();

    for (var i = 0; i < before.length; i++) {
      expect(identical(before[i], after[i]), isTrue, reason: 'index $i');
    }
  });

  test('a previous account\'s purchase error is cleared', () async {
    await container.read(purchaseSubmissionProvider.future);
    container.read(purchaseSubmissionProvider.notifier).state =
        const AsyncValue.error('INSUFFICIENT_BALANCE', StackTrace.empty);

    signedInUser.state = 'user-b';

    expect(await container.read(purchaseSubmissionProvider.future), isNull);
    expect(container.read(purchaseSubmissionProvider).hasError, isFalse);
  });
}
