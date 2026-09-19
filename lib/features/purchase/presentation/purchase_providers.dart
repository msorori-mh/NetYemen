// lib/features/purchase/presentation/purchase_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/app_config_provider.dart';
import '../../../core/utils/uuid_generator.dart';
import '../../auth/presentation/customer_session_providers.dart';
import '../data/purchase_repository.dart';
import '../data/supabase_purchase_repository.dart';
import '../data/fake_purchase_repository.dart';
import '../domain/entities.dart';

final purchaseRepositoryProvider = Provider<PurchaseRepository>((ref) {
  final config = ref.watch(appConfigProvider);
  if (config.isDemoMode || !config.isConfigured) {
    return FakePurchaseRepository();
  }
  return SupabasePurchaseRepository(Supabase.instance.client);
});

final purchaseHistoryProvider = FutureProvider<List<PurchaseOrder>>((
  ref,
) async {
  final repo = ref.watch(purchaseRepositoryProvider);
  return await repo.getMyPurchaseOrders();
});

final fulfillmentRecordsProvider = FutureProvider<List<FulfillmentRecord>>((
  ref,
) async {
  final repo = ref.watch(purchaseRepositoryProvider);
  return await repo.getMyFulfillmentRecords();
});

final purchaseDetailProvider = FutureProvider.family<PurchaseOrder?, String>((
  ref,
  purchaseId,
) async {
  final repo = ref.watch(purchaseRepositoryProvider);
  final orders = await repo.getMyPurchaseOrders();
  try {
    return orders.firstWhere((o) => o.id == purchaseId);
  } on StateError catch (_) {
    return null;
  }
});

class PurchaseIdempotencySession {
  final String key;
  final String fingerprint;

  const PurchaseIdempotencySession({
    required this.key,
    required this.fingerprint,
  });
}

class PurchaseSubmissionNotifier extends AsyncNotifier<Map<String, dynamic>?> {
  PurchaseIdempotencySession? _pendingSession;
  Future<Map<String, dynamic>>? _inFlight;
  String? _inFlightFingerprint;

  @override
  Future<Map<String, dynamic>?> build() async => null;

  Future<Map<String, dynamic>> submit(String packageId) async {
    final userId = ref.read(currentUserProvider)?.id ?? '';
    final fingerprint = '$userId:$packageId';

    final activeRequest = _inFlight;
    if (activeRequest != null) {
      if (_inFlightFingerprint == fingerprint) return await activeRequest;
      throw StateError('PURCHASE_ALREADY_IN_PROGRESS');
    }

    final request = _submitOnce(
      packageId: packageId,
      fingerprint: fingerprint,
    );
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

  Future<Map<String, dynamic>> _submitOnce({
    required String packageId,
    required String fingerprint,
  }) async {
    state = const AsyncValue.loading();

    final session = _pendingSession;
    final idempotencyKey = session != null && session.fingerprint == fingerprint
        ? session.key
        : UuidGenerator.generateV4();
    _pendingSession = PurchaseIdempotencySession(
      key: idempotencyKey,
      fingerprint: fingerprint,
    );

    try {
      final repository = ref.read(purchaseRepositoryProvider);
      final result = await repository.purchasePackage(
        packageId: packageId,
        idempotencyKey: idempotencyKey,
      );
      _pendingSession = null;
      state = AsyncValue.data(result);
      return result;
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
      rethrow;
    }
  }
}

final purchaseSubmissionProvider =
    AsyncNotifierProvider<PurchaseSubmissionNotifier, Map<String, dynamic>?>(
  PurchaseSubmissionNotifier.new,
);

class CardRevealNotifier extends AsyncNotifier<CardRevealResult?> {
  @override
  Future<CardRevealResult?> build() async => null;

  Future<void> reveal(String purchaseId) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(purchaseRepositoryProvider);
      return await repo.revealPurchaseCardSecret(purchaseId);
    });
  }

  Future<void> reset() async => state = const AsyncValue.data(null);
}

final cardRevealNotifierProvider =
    AsyncNotifierProvider<CardRevealNotifier, CardRevealResult?>(
  CardRevealNotifier.new,
);
