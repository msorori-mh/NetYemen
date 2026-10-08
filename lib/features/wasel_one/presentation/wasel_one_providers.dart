import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config_provider.dart';
import '../../../core/demo/demo_wallet_store.dart';
import '../../../core/utils/uuid_generator.dart';
import '../../auth/presentation/customer_session_providers.dart';
import '../../wallet/presentation/wallet_providers.dart';
import '../data/fake_wasel_one_repository.dart';
import '../data/supabase_wasel_one_repository.dart';
import '../data/wasel_one_repository.dart';
import '../domain/entities.dart';

final waselOneRepositoryProvider = Provider<WaselOneRepository>((ref) {
  // Per-user data: rebuild (and drop cached data) when the account changes.
  ref.watch(currentUserIdProvider);
  final config = ref.watch(appConfigProvider);
  if (config.isDemoMode || !config.isConfigured) {
    return FakeWaselOneRepository(ref.watch(demoWalletStoreProvider));
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

class WaselOnePurchaseSession {
  final String key;
  final String fingerprint;

  const WaselOnePurchaseSession({
    required this.key,
    required this.fingerprint,
  });
}

class WaselOnePurchaseNotifier extends AsyncNotifier<WaselOnePurchaseResult?> {
  WaselOnePurchaseSession? _pendingSession;
  Future<WaselOnePurchaseResult>? _inFlight;
  String? _inFlightFingerprint;

  @override
  Future<WaselOnePurchaseResult?> build() async {
    ref.watch(currentUserIdProvider);
    return null;
  }

  Future<WaselOnePurchaseResult> purchase(String planId) async {
    final userId = ref.read(currentUserProvider)?.id ?? 'demo';
    final fingerprint = '$userId:$planId';
    final activeRequest = _inFlight;
    if (activeRequest != null) {
      if (_inFlightFingerprint == fingerprint) return activeRequest;
      throw StateError('WASEL_ONE_PURCHASE_ALREADY_IN_PROGRESS');
    }

    final request = _purchaseOnce(planId, fingerprint);
    _inFlight = request;
    _inFlightFingerprint = fingerprint;
    try {
      return await request;
    } finally {
      if (identical(_inFlight, request)) {
        _inFlight = null;
        _inFlightFingerprint = null;
      }
    }
  }

  Future<WaselOnePurchaseResult> _purchaseOnce(
    String planId,
    String fingerprint,
  ) async {
    state = const AsyncValue.loading();
    final previous = _pendingSession;
    final key = previous != null && previous.fingerprint == fingerprint
        ? previous.key
        : UuidGenerator.generateV4();
    _pendingSession = WaselOnePurchaseSession(
      key: key,
      fingerprint: fingerprint,
    );

    try {
      final result = await ref
          .read(waselOneRepositoryProvider)
          .purchasePlan(planId: planId, idempotencyKey: key);
      _pendingSession = null;
      state = AsyncValue.data(result);
      ref.invalidate(waselOneEntitlementsProvider);
      // The plan was paid from the wallet: refresh the balance even when the
      // screen that started the purchase is no longer mounted.
      ref.invalidate(walletSummaryProvider);
      return result;
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
      rethrow;
    }
  }

  void clear() => state = const AsyncValue.data(null);
}

final waselOnePurchaseProvider =
    AsyncNotifierProvider<WaselOnePurchaseNotifier, WaselOnePurchaseResult?>(
  WaselOnePurchaseNotifier.new,
);

class WaselOneCredentialNotifier
    extends AsyncNotifier<RadiusAccessCredential?> {
  @override
  Future<RadiusAccessCredential?> build() async {
    // Reset any result or error left by a previous account.
    ref.watch(currentUserIdProvider);
    return null;
  }

  Future<RadiusAccessCredential>? _issuing;

  Future<RadiusAccessCredential> issue(String entitlementId) async {
    // Coalesce overlapping calls: one tap, one issued credential.
    final active = _issuing;
    if (active != null) return await active;
    final request = _issueOnce(entitlementId);
    _issuing = request;
    try {
      return await request;
    } finally {
      if (identical(_issuing, request)) _issuing = null;
    }
  }

  Future<RadiusAccessCredential> _issueOnce(String entitlementId) async {
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

  bool _busy = false;

  /// Claims the single "issue and show a credential" slot.
  ///
  /// Returns false when a credential is already being issued or is still
  /// displayed. Issuing a new credential revokes the previous one, so a
  /// second tap must not go through. Balance with [finish].
  bool tryBegin() {
    if (_busy) return false;
    _busy = true;
    return true;
  }

  /// Releases the slot claimed by [tryBegin] and drops the shown credential.
  void finish() {
    _busy = false;
    clear();
  }
}

final waselOneCredentialProvider =
    AsyncNotifierProvider<WaselOneCredentialNotifier, RadiusAccessCredential?>(
  WaselOneCredentialNotifier.new,
);
