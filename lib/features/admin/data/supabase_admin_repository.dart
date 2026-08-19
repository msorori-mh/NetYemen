import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/entities.dart';
import 'admin_repository.dart';

class SupabaseAdminRepository implements AdminRepository {
  final SupabaseClient _client;

  SupabaseAdminRepository(this._client);

  @override
  Future<AdminDashboardKpi> fetchDashboardKpis() async {
    final result = await _client.rpc<Map<String, dynamic>>(
      'admin_dashboard_kpis',
    );
    return AdminDashboardKpi.fromJson(result);
  }

  @override
  Future<List<AdminNetworkRequest>> fetchPendingRequests({
    String? status,
  }) async {
    var query = _client.from('network_addition_requests').select(
          'id, requester_user_id, idempotency_key, proposed_network_name, '
          'observed_ssid_display, observed_ssid_normalized, governorate, city, '
          'district, notes, status, duplicate_of, matched_network_id, '
          'resolution_note, created_at, updated_at, resolved_at, resolved_by, '
          'profiles!requester_user_id(full_name), '
          'networks!matched_network_id(commercial_name, status, verification_status)',
        );

    if (status != null && status.isNotEmpty) {
      query = query.eq('status', status);
    }

    final response = await query.order('created_at', ascending: false);
    return (response as List)
        .map(
          (json) => AdminNetworkRequest.fromJson(json as Map<String, dynamic>),
        )
        .toList();
  }

  @override
  Future<AdminNetworkRequest> resolveRequest(
    String requestId,
    String newStatus, {
    String? note,
    String? matchedNetworkId,
  }) async {
    await _client.rpc<Map<String, dynamic>>(
      'resolve_network_addition_request',
      params: {
        'p_request_id': requestId,
        'p_new_status': newStatus,
        'p_resolution_note': note,
        'p_matched_network_id': matchedNetworkId,
      },
    );

    final detail = await _client
        .from('network_addition_requests')
        .select(
          'id, requester_user_id, idempotency_key, proposed_network_name, '
          'observed_ssid_display, observed_ssid_normalized, governorate, city, '
          'district, notes, status, duplicate_of, matched_network_id, '
          'resolution_note, created_at, updated_at, resolved_at, resolved_by, '
          'profiles!requester_user_id(full_name), '
          'networks!matched_network_id(commercial_name, status, verification_status)',
        )
        .eq('id', requestId)
        .single();

    return AdminNetworkRequest.fromJson(detail);
  }

  @override
  Future<List<AdminNetwork>> fetchNetworks({
    String? status,
    String? verificationStatus,
  }) async {
    var query = _client.from('networks').select(
          'id, commercial_name, description, governorate, city, district, '
          'status, verification_status, created_by, approved_by, approved_at, '
          'created_at, updated_at, '
          'network_memberships(network_id, user_id, membership_role, status, profiles!user_id(full_name))',
        );

    if (status != null && status.isNotEmpty) {
      query = query.eq('status', status);
    }
    if (verificationStatus != null && verificationStatus.isNotEmpty) {
      query = query.eq('verification_status', verificationStatus);
    }

    final response = await query.order('created_at', ascending: false);
    return (response as List)
        .map((json) => AdminNetwork.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<AdminNetwork> approveNetwork(String networkId, {String? note}) async {
    await _client.rpc<Map<String, dynamic>>(
      'admin_approve_network',
      params: {'p_network_id': networkId, 'p_resolution_note': note},
    );
    return _fetchNetworkById(networkId);
  }

  @override
  Future<AdminNetwork> suspendNetwork(
    String networkId, {
    String? reason,
  }) async {
    await _client.rpc<Map<String, dynamic>>(
      'admin_suspend_network',
      params: {'p_network_id': networkId, 'p_reason': reason},
    );
    return _fetchNetworkById(networkId);
  }

  Future<AdminNetwork> _fetchNetworkById(String networkId) async {
    final detail = await _client
        .from('networks')
        .select(
          'id, commercial_name, description, governorate, city, district, '
          'status, verification_status, created_by, approved_by, approved_at, '
          'created_at, updated_at, '
          'network_memberships(network_id, user_id, membership_role, status, profiles!user_id(full_name))',
        )
        .eq('id', networkId)
        .single();

    return AdminNetwork.fromJson(detail);
  }

  @override
  Future<List<AdminSsidAlias>> fetchNetworkAliases(String networkId) async {
    final response = await _client
        .from('network_ssid_aliases')
        .select()
        .eq('network_id', networkId)
        .order('created_at', ascending: false);

    return (response as List)
        .map((json) => AdminSsidAlias.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<AdminSsidAlias> verifyAlias(String aliasId) async {
    await _client.rpc<Map<String, dynamic>>(
      'admin_verify_ssid_alias',
      params: {'p_alias_id': aliasId},
    );
    return _fetchAliasById(aliasId);
  }

  @override
  Future<AdminSsidAlias> rejectAlias(String aliasId, {String? reason}) async {
    await _client.rpc<Map<String, dynamic>>(
      'admin_reject_ssid_alias',
      params: {'p_alias_id': aliasId, 'p_reason': reason},
    );
    return _fetchAliasById(aliasId);
  }

  Future<AdminSsidAlias> _fetchAliasById(String aliasId) async {
    final detail = await _client
        .from('network_ssid_aliases')
        .select()
        .eq('id', aliasId)
        .single();

    return AdminSsidAlias.fromJson(detail);
  }

  @override
  Future<List<AdminPackageInventory>> fetchPackages({String? networkId}) async {
    var query = _client.from('network_packages').select(
          'id, network_id, name, description, price, currency, duration_value, '
          'duration_unit, speed_mbps, package_type, status, is_public, sort_order, '
          'created_by, created_at, updated_at, '
          'package_inventory_balances(total_units, available_units)',
        );

    if (networkId != null && networkId.isNotEmpty) {
      query = query.eq('network_id', networkId);
    }

    final response = await query
        .order('sort_order', ascending: true)
        .order('created_at', ascending: false);
    return (response as List)
        .map(
          (json) =>
              AdminPackageInventory.fromJson(json as Map<String, dynamic>),
        )
        .toList();
  }

  @override
  Future<List<AdminUser>> fetchUsers() async {
    final response = await _client
        .from('profiles')
        .select('id, full_name, account_status, user_roles(role)')
        .order('full_name', ascending: true);

    return (response as List)
        .map((json) => AdminUser.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<AdminNetworkMembership>> fetchNetworkMemberships({
    String? networkId,
  }) async {
    var query = _client.from('network_memberships').select(
          'network_id, user_id, membership_role, status, created_at, updated_at, '
          'created_by, profiles!user_id(full_name)',
        );

    if (networkId != null && networkId.isNotEmpty) {
      query = query.eq('network_id', networkId);
    }

    final response = await query.order('created_at', ascending: false);
    return (response as List)
        .map(
          (json) =>
              AdminNetworkMembership.fromJson(json as Map<String, dynamic>),
        )
        .toList();
  }

  @override
  Future<Map<String, dynamic>> ingestCardVaultBatch({
    required String networkId,
    required String packageId,
    required List<Map<String, dynamic>> cards,
    String keyVersion = 'v1-test',
  }) async {
    final result = await _client.rpc<Map<String, dynamic>>(
      'admin_ingest_card_vault_batch',
      params: {
        'p_network_id': networkId,
        'p_package_id': packageId,
        'p_cards': cards,
        'p_key_version': keyVersion,
      },
    );
    return result;
  }

  @override
  Future<List<AdminAuditEvent>> fetchAuditEvents() async {
    final response = await _client
        .from('audit_events')
        .select()
        .order('occurred_at', ascending: false)
        .limit(200);

    return (response as List)
        .map((json) => AdminAuditEvent.fromJson(json as Map<String, dynamic>))
        .toList();
  }
}
