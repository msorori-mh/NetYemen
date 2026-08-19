import '../domain/entities.dart';
import 'network_request_repository.dart';

class FakeNetworkRequestRepository implements NetworkRequestRepository {
  final List<NetworkAdditionRequest> _requests;
  final Map<String, NetworkAdditionRequest> _idempotency;
  bool shouldThrow;

  FakeNetworkRequestRepository({
    List<NetworkAdditionRequest> requests = const [],
    Map<String, NetworkAdditionRequest>? idempotency,
    this.shouldThrow = false,
  })  : _requests = List.of(requests),
        _idempotency = idempotency != null
            ? Map<String, NetworkAdditionRequest>.from(idempotency)
            : {};

  List<NetworkAdditionRequest> get requests => List.unmodifiable(_requests);

  List<String> get idempotencyKeys => List.unmodifiable(_idempotency.keys);

  @override
  Future<List<NetworkAdditionRequest>> fetchMyRequests() async {
    if (shouldThrow) throw Exception('فشل تحميل الطلبات');
    await Future.delayed(const Duration(milliseconds: 200));
    return List.of(_requests);
  }

  @override
  Future<NetworkAdditionRequest> submitRequest({
    required String idempotencyKey,
    required String observedSsidDisplay,
    String? proposedNetworkName,
    String? governorate,
    String? city,
    String? district,
    String? notes,
  }) async {
    if (shouldThrow) throw Exception('فشل إرسال الطلب');
    await Future.delayed(const Duration(milliseconds: 200));

    final existing = _idempotency[idempotencyKey];
    if (existing != null) {
      return existing;
    }

    final request = NetworkAdditionRequest(
      id: 'fake-${DateTime.now().millisecondsSinceEpoch}',
      status: 'submitted',
      observedSsidDisplay: observedSsidDisplay,
      proposedNetworkName: proposedNetworkName,
      governorate: governorate,
      city: city,
      district: district,
      notes: notes,
      createdAt: DateTime.now(),
    );

    _idempotency[idempotencyKey] = request;
    _requests.insert(0, request);
    return request;
  }

  @override
  Future<NetworkAdditionRequest> cancelRequest(String requestId) async {
    if (shouldThrow) throw Exception('فشل إلغاء الطلب');
    await Future.delayed(const Duration(milliseconds: 100));

    final index = _requests.indexWhere((r) => r.id == requestId);
    if (index == -1) throw Exception('الطلب غير موجود');

    final original = _requests[index];
    final cancelled = NetworkAdditionRequest(
      id: original.id,
      status: 'cancelled',
      observedSsidDisplay: original.observedSsidDisplay,
      proposedNetworkName: original.proposedNetworkName,
      governorate: original.governorate,
      city: original.city,
      district: original.district,
      notes: original.notes,
      createdAt: original.createdAt,
    );
    _requests[index] = cancelled;
    return cancelled;
  }
}
