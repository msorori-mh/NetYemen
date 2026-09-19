// lib/features/wallet/presentation/wallet_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/utils/uuid_generator.dart';
import '../../../providers/app_providers.dart';
import '../data/wallet_repository.dart';
import '../data/supabase_wallet_repository.dart';
import '../data/fake_wallet_repository.dart';
import '../domain/entities.dart';

final walletRepositoryProvider = Provider<WalletRepository>((ref) {
  final config = ref.watch(appConfigProvider);
  if (config.isDemoMode || !config.isConfigured) {
    return FakeWalletRepository();
  }
  return SupabaseWalletRepository(Supabase.instance.client);
});

final walletSummaryProvider = FutureProvider<WalletSummary>((ref) async {
  final repo = ref.watch(walletRepositoryProvider);
  return await repo.getMyWalletSummary();
});

final depositHistoryProvider = FutureProvider<List<DepositRequest>>((
  ref,
) async {
  final repo = ref.watch(walletRepositoryProvider);
  return await repo.getMyDepositRequests();
});

final depositChannelsProvider = FutureProvider<List<DepositChannel>>((
  ref,
) async {
  final repo = ref.watch(walletRepositoryProvider);
  return await repo.getActiveDepositChannels();
});

class DepositIdempotencySession {
  final String key;
  final String fingerprint;

  const DepositIdempotencySession({
    required this.key,
    required this.fingerprint,
  });
}

class DepositSubmissionNotifier extends AsyncNotifier<String?> {
  DepositIdempotencySession? _pendingSession;
  Future<String>? _inFlight;
  String? _inFlightFingerprint;

  @override
  Future<String?> build() async => null;

  Future<String> submit({
    required int amount,
    required String paymentDestinationId,
    String? proofReference,
  }) async {
    final trimmedReference = proofReference?.trim();
    final normalizedReference =
        trimmedReference == null || trimmedReference.isEmpty
            ? null
            : trimmedReference;
    final userId = ref.read(currentUserProvider)?.id ?? '';
    final fingerprint = '$userId|$amount|$paymentDestinationId|'
        '${normalizedReference ?? ''}';

    final activeRequest = _inFlight;
    if (activeRequest != null) {
      if (_inFlightFingerprint == fingerprint) return await activeRequest;
      throw StateError('DEPOSIT_ALREADY_IN_PROGRESS');
    }

    final request = _submitOnce(
      amount: amount,
      paymentDestinationId: paymentDestinationId,
      proofReference: normalizedReference,
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

  Future<String> _submitOnce({
    required int amount,
    required String paymentDestinationId,
    required String? proofReference,
    required String fingerprint,
  }) async {
    state = const AsyncValue.loading();

    final session = _pendingSession;
    final idempotencyKey = session != null && session.fingerprint == fingerprint
        ? session.key
        : UuidGenerator.generateV4();
    _pendingSession = DepositIdempotencySession(
      key: idempotencyKey,
      fingerprint: fingerprint,
    );

    try {
      final repository = ref.read(walletRepositoryProvider);
      final requestId = await repository.createDepositRequest(
        amount: amount,
        idempotencyKey: idempotencyKey,
        paymentDestinationId: paymentDestinationId,
        proofReference: proofReference,
      );
      _pendingSession = null;
      state = AsyncValue.data(requestId);
      return requestId;
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
      rethrow;
    }
  }
}

final depositSubmissionProvider =
    AsyncNotifierProvider<DepositSubmissionNotifier, String?>(
  DepositSubmissionNotifier.new,
);
