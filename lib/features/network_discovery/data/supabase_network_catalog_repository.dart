import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/entities.dart';
import 'network_catalog_repository.dart';

class SupabaseNetworkCatalogRepository implements NetworkCatalogRepository {
  final SupabaseClient _client;

  SupabaseNetworkCatalogRepository(this._client);

  @override
  Future<List<NetworkEntity>> fetchApprovedNetworks() async {
    final networkResponse = await _client
        .from('networks')
        .select('id, commercial_name, description, governorate, city, district')
        .eq('status', 'active')
        .eq('verification_status', 'verified')
        .order('commercial_name');

    final networks = (networkResponse as List)
        .map((j) => _parseNetwork(j))
        .toList();

    if (networks.isEmpty) return [];

    final networkIds = networks.map((n) => n.id).toList();

    final aliasResponse = await _client
        .from('network_ssid_aliases')
        .select('id, network_id, ssid_display, ssid_normalized')
        .eq('status', 'active')
        .inFilter('network_id', networkIds);

    final aliases = (aliasResponse as List)
        .map((j) => SsidAlias(
              id: j['id'] as String,
              networkId: j['network_id'] as String,
              ssidDisplay: j['ssid_display'] as String,
              ssidNormalized: j['ssid_normalized'] as String,
            ))
        .toList();

    final aliasMap = <String, List<SsidAlias>>{};
    for (final alias in aliases) {
      aliasMap.putIfAbsent(alias.networkId, () => []).add(alias);
    }

    return networks
        .map((n) => n.copyWith(ssidAliases: aliasMap[n.id] ?? []))
        .toList();
  }

  @override
  Future<NetworkEntity?> fetchNetworkDetail(String networkId) async {
    final response = await _client
        .from('networks')
        .select('id, commercial_name, description, governorate, city, district')
        .eq('id', networkId)
        .eq('status', 'active')
        .eq('verification_status', 'verified')
        .maybeSingle();

    if (response == null) return null;

    final network = _parseNetwork(response);

    final aliasResponse = await _client
        .from('network_ssid_aliases')
        .select('id, network_id, ssid_display, ssid_normalized')
        .eq('network_id', networkId)
        .eq('status', 'active');

    final aliases = (aliasResponse as List)
        .map((j) => SsidAlias(
              id: j['id'] as String,
              networkId: j['network_id'] as String,
              ssidDisplay: j['ssid_display'] as String,
              ssidNormalized: j['ssid_normalized'] as String,
            ))
        .toList();

    return network.copyWith(ssidAliases: aliases);
  }

  NetworkEntity _parseNetwork(Map<String, dynamic> json) {
    return NetworkEntity(
      id: json['id'] as String,
      commercialName: json['commercial_name'] as String? ?? '',
      description: json['description'] as String?,
      governorate: json['governorate'] as String?,
      city: json['city'] as String?,
      district: json['district'] as String?,
    );
  }
}
