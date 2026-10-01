import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/features/packages/domain/entities.dart';

void main() {
  group('NetworkPackage', () {
    const package = NetworkPackage(
      id: 'pkg-1',
      networkId: 'net-1',
      name: 'باقة يومية',
      description: 'وصف',
      price: 1000,
      currency: 'YER',
      durationValue: 1,
      durationUnit: 'day',
      speedMbps: 10,
      packageType: 'time',
      status: 'active',
      isPublic: true,
      sortOrder: 1,
    );

    test('parses from JSON', () {
      final json = {
        'id': 'pkg-1',
        'network_id': 'net-1',
        'name': 'باقة يومية',
        'description': 'وصف',
        'price': 1000,
        'currency': 'YER',
        'duration_value': 1,
        'duration_unit': 'day',
        'speed_mbps': 10,
        'package_type': 'time',
        'status': 'active',
        'is_public': true,
        'sort_order': 1,
        'created_by': 'user-1',
        'created_at': '2026-01-01T00:00:00Z',
      };

      final parsed = NetworkPackage.fromJson(json);
      expect(parsed.id, 'pkg-1');
      expect(parsed.networkId, 'net-1');
      expect(parsed.price, 1000);
      expect(parsed.isAvailableForPublic, isTrue);
    });

    test('displayPrice formats correctly', () {
      expect(package.displayPrice, '10 YER');
    });

    test('durationText localizes duration', () {
      expect(package.durationText, '1 يوم');
    });

    test('copyWith updates fields', () {
      final updated = package.copyWith(price: 2000, status: 'inactive');
      expect(updated.price, 2000);
      expect(updated.status, 'inactive');
      expect(updated.name, package.name);
    });

    test('isAvailableForPublic requires active and public', () {
      final inactive = package.copyWith(status: 'inactive');
      expect(inactive.isAvailableForPublic, isFalse);

      final hidden = package.copyWith(isPublic: false);
      expect(hidden.isAvailableForPublic, isFalse);
    });
  });

  group('PackageInventoryBalance', () {
    test('detects out of stock', () {
      const inStock = PackageInventoryBalance(
        packageId: 'pkg-1',
        networkId: 'net-1',
        totalUnits: 10,
        availableUnits: 5,
        isAvailable: true,
      );
      expect(inStock.isOutOfStock, isFalse);

      const outOfStock = PackageInventoryBalance(
        packageId: 'pkg-1',
        networkId: 'net-1',
        totalUnits: 10,
        availableUnits: 0,
        isAvailable: true,
      );
      expect(outOfStock.isOutOfStock, isTrue);
    });
  });

  group('PackageInventoryMovement', () {
    test('parses from JSON', () {
      final json = {
        'id': 'mov-1',
        'package_id': 'pkg-1',
        'network_id': 'net-1',
        'quantity_change': 10,
        'previous_total': 0,
        'new_total': 10,
        'previous_available': 0,
        'new_available': 10,
        'reason': 'إضافة مخزون',
        'actor_user_id': 'user-1',
        'created_at': '2026-01-01T00:00:00Z',
      };

      final movement = PackageInventoryMovement.fromJson(json);
      expect(movement.id, 'mov-1');
      expect(movement.quantityChange, 10);
      expect(movement.newAvailable, 10);
    });
  });
}
