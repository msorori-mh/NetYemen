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

final pendingIdempotencyKeyProvider = StateProvider<String?>((ref) => null);

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

      var idempotencyKey = _ref.read(pendingIdempotencyKeyProvider);
      if (idempotencyKey == null) {
        idempotencyKey = UuidGenerator.generateV4();
        _ref.read(pendingIdempotencyKeyProvider.notifier).state =
            idempotencyKey;
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
      _ref.read(pendingIdempotencyKeyProvider.notifier).state = null;

      _ref.read(myRequestsProvider.notifier).refresh();

      return result;
    } catch (e, st) {
      _ref.read(submitRequestStateProvider.notifier).state =
          AsyncValue.error(e, st);
      rethrow;
    }
  }

  void resetIdempotency() {
    _ref.read(pendingIdempotencyKeyProvider.notifier).state = null;
    _ref.read(submitRequestStateProvider.notifier).state = null;
  }
}
