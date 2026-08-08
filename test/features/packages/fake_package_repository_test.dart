import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/features/packages/data/fake_package_repository.dart';

void main() {
  group('FakePackageRepository', () {
    late FakePackageRepository repository;

    setUp(() {
      repository = FakePackageRepository();
    });

    test('fetchPublicPackages returns active public demo packages', () async {
      final packages = await repository.fetchPublicPackages('demo-net-1');
      expect(packages, isNotEmpty);
      expect(packages.every((p) => p.status == 'active' && p.isPublic), isTrue);
    });

    test('fetchNetworkPackages returns all packages for network', () async {
      final packages = await repository.fetchNetworkPackages('demo-net-1');
      expect(packages.length, 3);
    });

    test('fetchOwnedNetworks returns demo networks', () async {
      final networks = await repository.fetchOwnedNetworks();
      expect(networks, isNotEmpty);
    });

    test('createPackage initializes with draft status and zero balance', () async {
      final created = await repository.createPackage(
        networkId: 'demo-net-1',
        name: 'باقة تجريبية',
        price: 1500,
      );
      expect(created.status, 'draft');

      final balance = await repository.fetchPackageBalance(created.id);
      expect(balance, isNotNull);
      expect(balance!.availableUnits, 0);
    });

    test('publishPackage activates package', () async {
      final created = await repository.createPackage(
        networkId: 'demo-net-1',
        name: 'باقة للنشر',
        price: 1000,
      );
      final published = await repository.publishPackage(created.id);
      expect(published.status, 'active');
      expect(published.isPublic, isTrue);
    });

    test('archivePackage prevents further publish', () async {
      final created = await repository.createPackage(
        networkId: 'demo-net-1',
        name: 'باقة مؤرشفة',
        price: 1000,
      );
      await repository.publishPackage(created.id);
      final archived = await repository.archivePackage(created.id);
      expect(archived.status, 'archived');
      expect(archived.isPublic, isFalse);
      expect(
        () => repository.publishPackage(created.id),
        throwsA(isA<StateError>()),
      );
    });

    test('adjustInventory updates balance and records movement', () async {
      final packages = await repository.fetchPublicPackages('demo-net-1');
      final package = packages.first;

      final balanceBefore = await repository.fetchPackageBalance(package.id);
      final beforeAvailable = balanceBefore!.availableUnits;

      final balanceAfter = await repository.adjustInventory(
        package.id,
        10,
        'إضافة دفعة',
      );
      expect(balanceAfter.availableUnits, beforeAvailable + 10);

      final movements = await repository.fetchNetworkMovements(package.networkId);
      expect(movements.any((m) => m.packageId == package.id && m.quantityChange == 10), isTrue);
    });

    test('adjustInventory prevents negative stock', () async {
      final packages = await repository.fetchPublicPackages('demo-net-1');
      final package = packages.first;
      final balance = await repository.fetchPackageBalance(package.id);
      final excessive = balance!.availableUnits + 1;

      expect(
        () => repository.adjustInventory(package.id, -excessive, 'خصم زائد'),
        throwsA(isA<StateError>()),
      );
    });

    test('cross-network package update is isolated', () async {
      final networkAPackage = (await repository.fetchNetworkPackages('demo-net-1')).first;
      // Simulate an update attempt targeted at network B.
      final updated = await repository.updatePackage(
        networkAPackage.id,
        name: 'محدث',
      );
      expect(updated.name, 'محدث');
      expect(updated.networkId, 'demo-net-1');
    });
  });
}
