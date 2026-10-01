import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config_provider.dart';
import '../../auth/presentation/customer_session_providers.dart';
import '../data/fake_wasel_one_repository.dart';
import '../data/supabase_wasel_one_repository.dart';
import '../data/wasel_one_repository.dart';
import '../domain/entities.dart';

final waselOneRepositoryProvider = Provider<WaselOneRepository>((ref) {
  // Per-user data: rebuild (and drop cached data) when the account changes.
  ref.watch(currentUserIdProvider);
  final config = ref.watch(appConfigProvider);
  if (config.isDemoMode || !config.isConfigured) {
    return FakeWaselOneRepository();
  }
  return SupabaseWaselOneRepository(Supabase.instance.client);
});

final waselOnePlansProvider = FutureProvider<List<FederatedAccessPlan>>((ref) {
  return ref.watch(waselOneRepositoryProvider).getPublicPlans();
});

final waselOneEntitlementsProvider = FutureProvider<List<AccessEntitlement>>((
  ref,
) {
  return ref.watch(waselOneRepositoryProvider).getMyEntitlements();
});

class WaselOneCredentialNotifier
    extends AsyncNotifier<RadiusAccessCredential?> {
  @override
  Future<RadiusAccessCredential?> build() async {
    // Reset any result or error left by a previous account.
    ref.watch(currentUserIdProvider);
    return null;
  }

  Future<RadiusAccessCredential> issue(String entitlementId) async {
    state = const AsyncValue.loading();
    try {
      final credential = await ref
          .read(waselOneRepositoryProvider)
          .issueAccessCredential(entitlementId);
      state = AsyncValue.data(credential);
      return credential;
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
      rethrow;
    }
  }

  void clear() => state = const AsyncValue.data(null);
}

final waselOneCredentialProvider =
    AsyncNotifierProvider<WaselOneCredentialNotifier, RadiusAccessCredential?>(
  WaselOneCredentialNotifier.new,
);
