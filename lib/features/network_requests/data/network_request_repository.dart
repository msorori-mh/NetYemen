import '../domain/entities.dart';

abstract class NetworkRequestRepository {
  Future<List<NetworkAdditionRequest>> fetchMyRequests();
  Future<NetworkAdditionRequest> submitRequest({
    required String idempotencyKey,
    required String observedSsidDisplay,
    String? proposedNetworkName,
    String? governorate,
    String? city,
    String? district,
    String? notes,
  });
  Future<NetworkAdditionRequest> cancelRequest(String requestId);
}
