import '../../network_discovery/domain/entities.dart';
import '../domain/entities.dart';

abstract class PackageRepository {
  /// Fetch networks owned by the authenticated user.
  Future<List<NetworkEntity>> fetchOwnedNetworks();

  /// Fetch a single package by id.
  Future<NetworkPackage?> fetchPackage(String packageId);

  /// Public customer-facing packages for an approved active network.
  Future<List<NetworkPackage>> fetchPublicPackages(String networkId);

  /// All packages visible to an owner/operator for a network.
  Future<List<NetworkPackage>> fetchNetworkPackages(String networkId);

  /// Inventory balance for a specific package.
  Future<PackageInventoryBalance?> fetchPackageBalance(String packageId);

  /// Recent inventory movements for a network.
  Future<List<PackageInventoryMovement>> fetchNetworkMovements(String networkId);

  /// Create a new package (owner only).
  Future<NetworkPackage> createPackage({
    required String networkId,
    required String name,
    String? description,
    required int price,
    String currency,
    int? durationValue,
    String? durationUnit,
    int? speedMbps,
    String packageType,
  });

  /// Update package metadata (owner only).
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
  });

  /// Publish a draft or inactive package (owner only).
  Future<NetworkPackage> publishPackage(String packageId);

  /// Deactivate an active package (owner only).
  Future<NetworkPackage> deactivatePackage(String packageId);

  /// Archive a package (owner only).
  Future<NetworkPackage> archivePackage(String packageId);

  /// Adjust package inventory (owner or operator).
  Future<PackageInventoryBalance> adjustInventory(
    String packageId,
    int quantityChange,
    String reason, {
    String? idempotencyKey,
  });
}
