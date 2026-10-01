import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/utils/uuid_generator.dart';
import '../../network_discovery/domain/entities.dart';
import '../domain/entities.dart';
import 'package_repository.dart';

class SupabasePackageRepository implements PackageRepository {
  final SupabaseClient _client;

  SupabasePackageRepository(this._client);

  @override
  Future<List<NetworkEntity>> fetchOwnedNetworks() async {
    final response = await _client.rpc<List<dynamic>>('get_owned_networks');
    return response
        .map((json) => _parseNetwork(json as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<NetworkPackage?> fetchPackage(String packageId) async {
    return _fetchPackageById(packageId);
  }

  NetworkEntity _parseNetwork(Map<String, dynamic> json) {
    return NetworkEntity(
      id: json['id'] as String? ?? '',
      commercialName: json['commercial_name'] as String? ?? '',
      description: json['description'] as String?,
      governorate: json['governorate'] as String?,
      city: json['city'] as String?,
      district: json['district'] as String?,
    );
  }

  @override
  Future<List<NetworkPackage>> fetchPublicPackages(String networkId) async {
    final response = await _client
        .from('network_packages')
        .select()
        .eq('network_id', networkId)
        .eq('status', 'active')
        .eq('is_public', true)
        .order('sort_order', ascending: true)
        .order('created_at', ascending: false);

    return (response as List)
        .map((json) => NetworkPackage.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<NetworkPackage>> fetchNetworkPackages(String networkId) async {
    final response = await _client
        .from('network_packages')
        .select()
        .eq('network_id', networkId)
        .order('sort_order', ascending: true)
        .order('created_at', ascending: false);

    return (response as List)
        .map((json) => NetworkPackage.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<PackageInventoryBalance?> fetchPackageBalance(String packageId) async {
    final response = await _client
        .from('package_inventory_balances')
        .select()
        .eq('package_id', packageId)
        .maybeSingle();

    if (response == null) return null;
    return PackageInventoryBalance.fromJson(response);
  }

  @override
  Future<List<PackageInventoryMovement>> fetchNetworkMovements(
    String networkId,
  ) async {
    final response = await _client
        .from('package_inventory_movements')
        .select()
        .eq('network_id', networkId)
        .order('created_at', ascending: false)
        .limit(50);

    return (response as List)
        .map(
          (json) =>
              PackageInventoryMovement.fromJson(json as Map<String, dynamic>),
        )
        .toList();
  }

  @override
  Future<NetworkPackage> createPackage({
    required String networkId,
    required String name,
    String? description,
    required int price,
    String currency = 'YER',
    int? durationValue,
    String? durationUnit,
    int? speedMbps,
    String packageType = 'time',
  }) async {
    final packageId = await _client.rpc<String>(
      'create_network_package',
      params: {
        'p_network_id': networkId,
        'p_name': name,
        'p_description': description,
        'p_price': price,
        'p_currency': currency,
        'p_duration_value': durationValue,
        'p_duration_unit': durationUnit,
        'p_speed_mbps': speedMbps,
        'p_package_type': packageType,
      },
    );

    final package = await _fetchPackageById(packageId);
    return package ?? (throw StateError('Created package not found'));
  }

  @override
  Future<NetworkPackage> updatePackage(
    String packageId, {
    String? name,
    String? description,
    int? price,
    String? currency,
    int? durationValue,
    String? durationUnit,
    int? speedMbps,
    String? packageType,
    int? sortOrder,
  }) async {
    await _client.rpc<Map<String, dynamic>>(
      'update_network_package',
      params: {
        'p_package_id': packageId,
        'p_name': name,
        'p_description': description,
        'p_price': price,
        'p_currency': currency,
        'p_duration_value': durationValue,
        'p_duration_unit': durationUnit,
        'p_speed_mbps': speedMbps,
        'p_package_type': packageType,
        'p_sort_order': sortOrder,
      },
    );

    final package = await _fetchPackageById(packageId);
    return package ?? (throw StateError('Updated package not found'));
  }

  @override
  Future<NetworkPackage> publishPackage(String packageId) async {
    await _client.rpc<Map<String, dynamic>>(
      'publish_network_package',
      params: {'p_package_id': packageId},
    );

    final package = await _fetchPackageById(packageId);
    return package ?? (throw StateError('Published package not found'));
  }

  @override
  Future<NetworkPackage> deactivatePackage(String packageId) async {
    await _client.rpc<Map<String, dynamic>>(
      'deactivate_network_package',
      params: {'p_package_id': packageId},
    );

    final package = await _fetchPackageById(packageId);
    return package ?? (throw StateError('Deactivated package not found'));
  }

  @override
  Future<NetworkPackage> archivePackage(String packageId) async {
    await _client.rpc<Map<String, dynamic>>(
      'archive_network_package',
      params: {'p_package_id': packageId},
    );

    final package = await _fetchPackageById(packageId);
    return package ?? (throw StateError('Archived package not found'));
  }

  @override
  Future<PackageInventoryBalance> adjustInventory(
    String packageId,
    int quantityChange,
    String reason, {
    String? idempotencyKey,
  }) async {
    final key = idempotencyKey ?? UuidGenerator.generateV4();

    final result = await _client.rpc<Map<String, dynamic>>(
      'adjust_package_inventory',
      params: {
        'p_package_id': packageId,
        'p_quantity_change': quantityChange,
        'p_reason': reason,
        'p_idempotency_key': key,
      },
    );

    final balance = await fetchPackageBalance(packageId);
    if (balance != null) return balance;

    // Fallback for the unlikely case the balance row is missing.
    final newTotal = (result['new_total'] as num?)?.toInt() ?? 0;
    final newAvailable = (result['new_available'] as num?)?.toInt() ?? 0;
    return PackageInventoryBalance(
      packageId: packageId,
      networkId: '',
      totalUnits: newTotal,
      availableUnits: newAvailable,
      isAvailable: newAvailable > 0,
    );
  }

  Future<NetworkPackage?> _fetchPackageById(String packageId) async {
    final response = await _client
        .from('network_packages')
        .select()
        .eq('id', packageId)
        .maybeSingle();

    if (response == null) return null;
    return NetworkPackage.fromJson(response);
  }
}
