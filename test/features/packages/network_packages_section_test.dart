import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/features/network_discovery/domain/entities.dart';
import 'package:netyemen/features/packages/data/package_repository.dart';
import 'package:netyemen/features/packages/domain/entities.dart';
import 'package:netyemen/features/packages/presentation/network_packages_section.dart';
import 'package:netyemen/features/packages/presentation/package_providers.dart';

class _FakeRepository implements PackageRepository {
  final List<NetworkPackage> publicPackages;
  final Map<String, PackageInventoryBalance> balances;

  _FakeRepository({
    required this.publicPackages,
    required this.balances,
  });

  @override
  Future<List<NetworkPackage>> fetchPublicPackages(String networkId) async {
    return publicPackages.where((p) => p.networkId == networkId).toList();
  }

  @override
  Future<List<NetworkPackage>> fetchNetworkPackages(String networkId) async =>
      [];

  @override
  Future<NetworkPackage?> fetchPackage(String packageId) async => null;

  @override
  Future<List<NetworkEntity>> fetchOwnedNetworks() async => [];

  @override
  Future<PackageInventoryBalance?> fetchPackageBalance(String packageId) async {
    return balances[packageId];
  }

  @override
  Future<List<PackageInventoryMovement>> fetchNetworkMovements(String networkId) async => [];

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
  }) async =>
      throw UnimplementedError();

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
  }) async =>
      throw UnimplementedError();

  @override
  Future<NetworkPackage> publishPackage(String packageId) async =>
      throw UnimplementedError();

  @override
  Future<NetworkPackage> deactivatePackage(String packageId) async =>
      throw UnimplementedError();

  @override
  Future<NetworkPackage> archivePackage(String packageId) async =>
      throw UnimplementedError();

  @override
  Future<PackageInventoryBalance> adjustInventory(
    String packageId,
    int quantityChange,
    String reason, {
    String? idempotencyKey,
  }) async =>
      throw UnimplementedError();
}

void main() {
  group('NetworkPackagesSection', () {
    testWidgets('renders loading state initially', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            packageRepositoryProvider.overrideWithValue(
              _FakeRepository(publicPackages: [], balances: {}),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: NetworkPackagesSection(networkId: 'net-1'),
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders empty state when no packages', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            packageRepositoryProvider.overrideWithValue(
              _FakeRepository(publicPackages: [], balances: {}),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: NetworkPackagesSection(networkId: 'net-1'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('لا توجد باقات متاحة حالياً'), findsOneWidget);
    });

    testWidgets('renders available and out-of-stock states', (tester) async {
      const inStockPackage = NetworkPackage(
        id: 'pkg-1',
        networkId: 'net-1',
        name: 'باقة متوفرة',
        price: 1000,
        currency: 'YER',
        durationValue: 1,
        durationUnit: 'day',
        packageType: 'time',
        status: 'active',
        isPublic: true,
        sortOrder: 1,
      );
      const outOfStockPackage = NetworkPackage(
        id: 'pkg-2',
        networkId: 'net-1',
        name: 'باقة نافدة',
        price: 500,
        currency: 'YER',
        durationValue: 1,
        durationUnit: 'hour',
        packageType: 'time',
        status: 'active',
        isPublic: true,
        sortOrder: 2,
      );

      final repository = _FakeRepository(
        publicPackages: const [inStockPackage, outOfStockPackage],
        balances: {
          'pkg-1': const PackageInventoryBalance(
            packageId: 'pkg-1',
            networkId: 'net-1',
            totalUnits: 10,
            availableUnits: 10,
            isAvailable: true,
          ),
          'pkg-2': const PackageInventoryBalance(
            packageId: 'pkg-2',
            networkId: 'net-1',
            totalUnits: 0,
            availableUnits: 0,
            isAvailable: true,
          ),
        },
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            packageRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: NetworkPackagesSection(networkId: 'net-1'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('باقة متوفرة'), findsOneWidget);
      expect(find.text('باقة نافدة'), findsOneWidget);
      expect(find.text('متوفر'), findsOneWidget);
      expect(find.text('غير متوفر'), findsOneWidget);
    });
  });
}
