import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/utils/uuid_generator.dart';
import '../../../providers/app_providers.dart';
import '../../network_discovery/presentation/network_discovery_providers.dart';
import '../../network_requests/data/fake_network_request_repository.dart';
import '../../network_requests/data/network_request_repository.dart';
import '../../network_requests/data/supabase_network_request_repository.dart';
import '../../network_requests/domain/entities.dart';

final networkRequestRepositoryProvider =
    Provider<NetworkRequestRepository>((ref) {
  final config = ref.watch(appConfigProvider);
  if (config.isDemoMode || !config.isConfigured) {
    return FakeNetworkRequestRepository();
  }
  return SupabaseNetworkRequestRepository(Supabase.instance.client);
});

final myRequestsProvider =
    AsyncNotifierProvider<MyRequestsNotifier, List<NetworkAdditionRequest>>(
  MyRequestsNotifier.new,
);

class MyRequestsNotifier extends AsyncNotifier<List<NetworkAdditionRequest>> {
  @override
  Future<List<NetworkAdditionRequest>> build() async {
    final config = ref.watch(appConfigProvider);
    final user = ref.watch(currentUserProvider);

    if (config.isConfigured && user == null) {
      return const [];
    }

    final repo = ref.read(networkRequestRepositoryProvider);
    return repo.fetchMyRequests();
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(networkRequestRepositoryProvider);
      return repo.fetchMyRequests();
    });
  }
}

final submitRequestStateProvider =
    StateProvider<AsyncValue<NetworkAdditionRequest>?>((ref) => null);

/// A pending idempotency session binds a single UUID to one immutable logical
/// request payload. The key is reused only while the payload fingerprint is
/// unchanged; any material change mints a new UUID.
class IdempotencySession {
  final String key;
  final String payloadFingerprint;

  const IdempotencySession(this.key, this.payloadFingerprint);
}

final pendingIdempotencySessionProvider =
    StateProvider<IdempotencySession?>((ref) => null);

final submitRequestNotifierProvider = Provider<SubmitRequestNotifier>((ref) {
  return SubmitRequestNotifier(ref);
});

class SubmitRequestNotifier {
  final Ref _ref;

  SubmitRequestNotifier(this._ref);

  Future<NetworkAdditionRequest> submit({
    required String observedSsidDisplay,
    String? proposedNetworkName,
    String? governorate,
    String? city,
    String? district,
    String? notes,
  }) async {
    _ref.read(submitRequestStateProvider.notifier).state =
        const AsyncValue.loading();

    try {
      final repo = _ref.read(networkRequestRepositoryProvider);
      final user = _ref.read(currentUserProvider);

      final fingerprint = _computeFingerprint(
        observedSsidDisplay: observedSsidDisplay,
        proposedNetworkName: proposedNetworkName,
        governorate: governorate,
        city: city,
        district: district,
        notes: notes,
        requesterUserId: user?.id,
      );

      final session = _ref.read(pendingIdempotencySessionProvider);
      final String idempotencyKey;
      if (session != null && session.payloadFingerprint == fingerprint) {
        idempotencyKey = session.key;
      } else {
        idempotencyKey = UuidGenerator.generateV4();
        _ref.read(pendingIdempotencySessionProvider.notifier).state =
            IdempotencySession(idempotencyKey, fingerprint);
      }

      final result = await repo.submitRequest(
        idempotencyKey: idempotencyKey,
        observedSsidDisplay: observedSsidDisplay,
        proposedNetworkName: proposedNetworkName,
        governorate: governorate,
        city: city,
        district: district,
        notes: notes,
      );

      _ref.read(submitRequestStateProvider.notifier).state =
          AsyncValue.data(result);
      _ref.read(pendingIdempotencySessionProvider.notifier).state = null;

      _ref.read(myRequestsProvider.notifier).refresh();

      return result;
    } catch (e, st) {
      _ref.read(submitRequestStateProvider.notifier).state =
          AsyncValue.error(e, st);
      rethrow;
    }
  }

  /// Clears any pending idempotency session. Called when a fresh logical request
  /// is started (e.g., opening the add-request screen).
  void resetIdempotency() {
    _ref.read(pendingIdempotencySessionProvider.notifier).state = null;
    _ref.read(submitRequestStateProvider.notifier).state = null;
  }

  /// Deterministic fingerprint of the logical request payload. Two payloads that
  /// differ only in surrounding whitespace are considered the same logical
  /// request. Requester identity is included so a key cannot silently migrate
  /// across users.
  String _computeFingerprint({
    required String observedSsidDisplay,
    String? proposedNetworkName,
    String? governorate,
    String? city,
    String? district,
    String? notes,
    String? requesterUserId,
  }) {
    final payload = <String, dynamic>{
      'observed_ssid_display': observedSsidDisplay.trim(),
      'proposed_network_name': (proposedNetworkName ?? '').trim(),
      'governorate': (governorate ?? '').trim(),
      'city': (city ?? '').trim(),
      'district': (district ?? '').trim(),
      'notes': (notes ?? '').trim(),
      'requester_user_id': requesterUserId ?? '',
    };
    return jsonEncode(payload);
  }
}
