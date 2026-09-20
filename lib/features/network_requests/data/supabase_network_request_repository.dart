import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/entities.dart';
import 'network_request_repository.dart';

class SupabaseNetworkRequestRepository implements NetworkRequestRepository {
  final SupabaseClient _client;

  SupabaseNetworkRequestRepository(this._client);

  @override
  Future<List<NetworkAdditionRequest>> fetchMyRequests() async {
    final response = await _client
        .from('network_addition_requests')
        .select(
          'id, status, observed_ssid_display, proposed_network_name, '
          'governorate, city, district, notes, resolution_note, '
          'matched_network_id, created_at, resolved_at',
        )
        .order('created_at', ascending: false);

    return (response as List)
        .map((j) => NetworkAdditionRequest.fromJson(j as Map<String, dynamic>))
        .toList();
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
    final result = await _client.rpc(
      'submit_network_addition_request',
      params: {
        'p_idempotency_key': idempotencyKey,
        'p_observed_ssid_display': observedSsidDisplay,
        'p_proposed_network_name': proposedNetworkName,
        'p_governorate': governorate,
        'p_city': city,
        'p_district': district,
        'p_notes': notes,
      },
    );

    final resultMap = result as Map<String, dynamic>;
    final requestId = resultMap['id'] as String;

    final detail = await _client
        .from('network_addition_requests')
        .select(
          'id, status, observed_ssid_display, proposed_network_name, '
          'governorate, city, district, notes, resolution_note, '
          'matched_network_id, created_at, resolved_at',
        )
        .eq('id', requestId)
        .single();

    return NetworkAdditionRequest.fromJson(detail);
  }

  @override
  Future<NetworkAdditionRequest> cancelRequest(String requestId) async {
    await _client.rpc(
      'cancel_network_addition_request',
      params: {'p_request_id': requestId},
    );

    final detail = await _client
        .from('network_addition_requests')
        .select(
          'id, status, observed_ssid_display, proposed_network_name, '
          'governorate, city, district, notes, resolution_note, '
          'matched_network_id, created_at, resolved_at',
        )
        .eq('id', requestId)
        .single();

    return NetworkAdditionRequest.fromJson(detail);
  }
}
