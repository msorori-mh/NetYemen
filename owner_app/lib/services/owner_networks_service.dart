import 'package:supabase_flutter/supabase_flutter.dart';

class OwnerNetworksService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> getNetworkPackages(String networkId) async {
    final response = await _client
        .from('network_packages')
        .select()
        .eq('network_id', networkId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> createNetworkPackage({
    required String networkId,
    required String name,
    String? description,
    required int price,
    required String currency,
    int? durationValue,
    String? durationUnit,
    int? speedMbps,
    required String packageType,
  }) async {
    await _client.rpc('create_network_package', params: {
      'p_network_id': networkId,
      'p_name': name,
      'p_description': description,
      'p_price': price,
      'p_currency': currency,
      'p_duration_value': durationValue,
      'p_duration_unit': durationUnit,
      'p_speed_mbps': speedMbps,
      'p_package_type': packageType,
    });
  }

  Future<void> updateNetworkPackage({
    required String packageId,
    required String name,
    String? description,
    required int price,
    required String currency,
    int? durationValue,
    String? durationUnit,
    int? speedMbps,
    required String packageType,
  }) async {
    await _client.rpc('update_network_package', params: {
      'p_package_id': packageId,
      'p_name': name,
      'p_description': description,
      'p_price': price,
      'p_currency': currency,
      'p_duration_value': durationValue,
      'p_duration_unit': durationUnit,
      'p_speed_mbps': speedMbps,
      'p_package_type': packageType,
    });
  }

  Future<void> publishNetworkPackage(String packageId) async {
    await _client.rpc('publish_network_package', params: {'p_package_id': packageId});
  }

  Future<void> deactivateNetworkPackage(String packageId) async {
    await _client.rpc('deactivate_network_package', params: {'p_package_id': packageId});
  }

  Future<List<Map<String, dynamic>>> getNetworkSsidAliases(String networkId) async {
    final response = await _client
        .from('network_ssid_aliases')
        .select()
        .eq('network_id', networkId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> createSsidAlias(String networkId, String ssidDisplay, String ssidNormalized) async {
    await _client.from('network_ssid_aliases').insert({
      'network_id': networkId,
      'ssid_display': ssidDisplay,
      'ssid_normalized': ssidNormalized,
      // status will default to 'pending_verification'
    });
  }
}
