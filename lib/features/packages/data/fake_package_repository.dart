import '../../../core/utils/uuid_generator.dart';
import '../../network_discovery/data/demo_network_catalog_repository.dart';
import '../../network_discovery/domain/entities.dart';
import '../domain/entities.dart';
import 'package_repository.dart';

class FakePackageRepository implements PackageRepository {
  final _packages = <String, NetworkPackage>{};
  final _balances = <String, PackageInventoryBalance>{};
  final _movements = <String, PackageInventoryMovement>{};
  static const _demoNetId = 'demo-net-1';

  FakePackageRepository() {
    _seedDemoPackages();
  }

  void _seedDemoPackages() {
    const demoNetId = _demoNetId;
    const packageIds = ['demo-pkg-1', 'demo-pkg-2', 'demo-pkg-3'];

    final packages = [
      NetworkPackage(
        id: packageIds[0],
        networkId: demoNetId,
        name: 'باقة يومية',
        description: 'إنترنت سريع لمدة 24 ساعة',
        price: 500,
        currency: 'YER',
        durationValue: 1,
        durationUnit: 'day',
        speedMbps: 10,
        packageType: 'time',
        status: 'active',
        isPublic: true,
        sortOrder: 1,
      ),
      NetworkPackage(
        id: packageIds[1],
        networkId: demoNetId,
        name: 'باقة أسبوعية',
        description: '7 أيام من الإنترنت غير المحدود',
        price: 2500,
        currency: 'YER',
        durationValue: 1,
        durationUnit: 'week',
        speedMbps: 20,
        packageType: 'time',
        status: 'active',
        isPublic: true,
        sortOrder: 2,
      ),
      NetworkPackage(
        id: packageIds[2],
        networkId: demoNetId,
        name: 'باقة شهرية',
        description: 'باقة اقتصادية لمدة 30 يوم',
        price: 8000,
        currency: 'YER',
        durationValue: 1,
        durationUnit: 'month',
        speedMbps: 50,
        packageType: 'time',
        status: 'active',
        isPublic: true,
        sortOrder: 3,
      ),
    ];

    for (var pkg in packages) {
      _packages[pkg.id] = pkg;
      _balances[pkg.id] = PackageInventoryBalance(
        packageId: pkg.id,
        networkId: demoNetId,
        totalUnits: 100,
        availableUnits: 100,
        isAvailable: true,
      );
    }
  }

  @override
  Future<List<NetworkEntity>> fetchOwnedNetworks() async {
    await Future.delayed(const Duration(milliseconds: 200));
    final demo = DemoNetworkCatalogRepository();
    return demo.fetchApprovedNetworks();
  }

  @override
  Future<NetworkPackage?> fetchPackage(String packageId) async {
    await Future.delayed(const Duration(milliseconds: 100));
    return _packages[packageId];
  }

  @override
  Future<List<NetworkPackage>> fetchPublicPackages(String networkId) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return _packages.values
        .where(
          (p) => p.networkId == networkId && p.status == 'active' && p.isPublic,
        )
        .toList();
  }

  @override
  Future<List<NetworkPackage>> fetchNetworkPackages(String networkId) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return _packages.values.where((p) => p.networkId == networkId).toList();
  }

  @override
  Future<PackageInventoryBalance?> fetchPackageBalance(String packageId) async {
    await Future.delayed(const Duration(milliseconds: 100));
    return _balances[packageId];
  }

  @override
  Future<List<PackageInventoryMovement>> fetchNetworkMovements(
    String networkId,
  ) async {
    await Future.delayed(const Duration(milliseconds: 150));
    return _movements.values.where((m) => m.networkId == networkId).toList();
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
    await Future.delayed(const Duration(milliseconds: 150));
    final package = NetworkPackage(
      id: 'fake-pkg-${UuidGenerator.generateV4()}',
      networkId: networkId,
      name: name,
      description: description,
      price: price,
      currency: currency,
      durationValue: durationValue,
      durationUnit: durationUnit,
      speedMbps: speedMbps,
      packageType: packageType,
      status: 'draft',
      isPublic: false,
      sortOrder: 0,
    );
    _packages[package.id] = package;
    _balances[package.id] = PackageInventoryBalance(
      packageId: package.id,
      networkId: networkId,
      totalUnits: 0,
      availableUnits: 0,
      isAvailable: true,
    );
    return package;
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
    await Future.delayed(const Duration(milliseconds: 150));
    final existing = _packages[packageId];
    if (existing == null) throw StateError('Package not found');

    final updated = existing.copyWith(
      name: name,
      description: description,
      price: price,
      currency: currency,
      durationValue: durationValue,
      durationUnit: durationUnit,
      speedMbps: speedMbps,
      packageType: packageType,
      sortOrder: sortOrder,
    );
    _packages[packageId] = updated;
    return updated;
  }

  @override
  Future<NetworkPackage> publishPackage(String packageId) async {
    await Future.delayed(const Duration(milliseconds: 150));
    final existing = _packages[packageId];
    if (existing?.status == 'archived') {
      throw StateError('Archived packages cannot be published');
    }
    return _setStatus(packageId, 'active', isPublic: true);
  }

  @override
  Future<NetworkPackage> deactivatePackage(String packageId) async {
    await Future.delayed(const Duration(milliseconds: 150));
    return _setStatus(packageId, 'inactive', isPublic: false);
  }

  @override
  Future<NetworkPackage> archivePackage(String packageId) async {
    await Future.delayed(const Duration(milliseconds: 150));
    return _setStatus(packageId, 'archived', isPublic: false);
  }

  @override
  Future<PackageInventoryBalance> adjustInventory(
    String packageId,
    int quantityChange,
    String reason, {
    String? idempotencyKey,
  }) async {
    await Future.delayed(const Duration(milliseconds: 150));
    final balance = _balances[packageId];
    if (balance == null) throw StateError('Balance not found');

    final newTotal = balance.totalUnits + quantityChange;
    final newAvailable = balance.availableUnits + quantityChange;

    if (newTotal < 0 || newAvailable < 0) {
      throw StateError('Insufficient stock');
    }

    final movement = PackageInventoryMovement(
      id: 'fake-mov-${UuidGenerator.generateV4()}',
      packageId: packageId,
      networkId: balance.networkId,
      quantityChange: quantityChange,
      previousTotal: balance.totalUnits,
      newTotal: newTotal,
      previousAvailable: balance.availableUnits,
      newAvailable: newAvailable,
      reason: reason,
      actorUserId: 'fake-user',
      createdAt: DateTime.now(),
    );
    _movements[movement.id] = movement;

    final updated = PackageInventoryBalance(
      packageId: packageId,
      networkId: balance.networkId,
      totalUnits: newTotal,
      availableUnits: newAvailable,
      isAvailable: newAvailable > 0,
    );
    _balances[packageId] = updated;
    return updated;
  }

  NetworkPackage _setStatus(
    String packageId,
    String status, {
    required bool isPublic,
  }) {
    final existing = _packages[packageId];
    if (existing == null) throw StateError('Package not found');
    final updated = existing.copyWith(status: status, isPublic: isPublic);
    _packages[packageId] = updated;
    return updated;
  }
}
