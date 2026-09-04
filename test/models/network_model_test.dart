import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/models/network_model.dart';

void main() {
  group('Network.fromJson', () {
    test(
        'correctly parses all fields including SSIDs, coordinates, and flags',
        () {
      final json = {
        'id': 'net-123',
        'owner_id': 'owner-456',
        'name': 'Yemen Net Fast',
        'description': 'شبكة سريعة وسط المدينة',
        'governorate': "Sana'a",
        'city': "Sana'a City",
        'district': 'Al Wahdah',
        'location_text': "Sana'a - Sana'a City - Al Wahdah",
        'lat': 15.3694,
        'lng': 44.1910,
        'is_approved': true,
        'is_active': true,
        'is_featured': true,
        'verified_badge': true,
        'network_ssids': [
          {'ssid': 'YemenNet_WiFi'},
          {'ssid': 'YemenNet_WiFi_5G'},
        ],
        'created_at': '2026-01-01T00:00:00.000Z',
      };

      final network = Network.fromJson(json);

      expect(network.id, 'net-123');
      expect(network.ownerId, 'owner-456');
      expect(network.name, 'Yemen Net Fast');
      expect(network.description, 'شبكة سريعة وسط المدينة');
      expect(network.governorate, "Sana'a");
      expect(network.city, "Sana'a City");
      expect(network.district, 'Al Wahdah');
      expect(network.lat, 15.3694);
      expect(network.lng, 44.1910);
      expect(network.isApproved, isTrue);
      expect(network.isActive, isTrue);
      expect(network.isFeatured, isTrue);
      expect(network.verifiedBadge, isTrue);
      expect(network.ssids, ['YemenNet_WiFi', 'YemenNet_WiFi_5G']);
      expect(network.displayLocation, "Sana'a - Sana'a City - Al Wahdah");
    });

    test('handles missing optional fields safely with default values', () {
      final json = {
        'id': 'net-789',
        'name': 'Minimal Net',
        'governorate': 'Aden',
        'city': 'Crater',
      };

      final network = Network.fromJson(json);

      expect(network.id, 'net-789');
      expect(network.name, 'Minimal Net');
      expect(network.governorate, 'Aden');
      expect(network.city, 'Crater');
      expect(network.district, isNull);
      expect(network.lat, isNull);
      expect(network.lng, isNull);
      expect(network.isApproved, isFalse);
      expect(network.isActive, isFalse);
      expect(network.isFeatured, isFalse);
      expect(network.ssids, isEmpty);
      expect(network.displayLocation, 'Aden - Crater');
    });
  });

  group('NetworkPrice.fromJson', () {
    test('parses full package metadata (BR-CARD-008)', () {
      final json = {
        'id': 'price-1',
        'network_id': 'net-123',
        'denomination': 1000,
        'selling_price': 1000,
        'data_quota_mb': 5120,
        'validity_minutes': 1440,
        'speed_limit_mbps': 10.5,
        'is_active': true,
      };

      final price = NetworkPrice.fromJson(json);

      expect(price.denomination, 1000);
      expect(price.sellingPrice, 1000);
      expect(price.dataQuotaMb, 5120);
      expect(price.validityMinutes, 1440);
      expect(price.speedLimitMbps, 10.5);
      expect(price.dataQuotaLabel, '5 جيجابايت');
      expect(price.validityLabel, '1 يوم');
    });

    test('formats sub-gigabyte quota and sub-day validity in smaller units',
        () {
      final json = {
        'id': 'price-2',
        'network_id': 'net-123',
        'denomination': 200,
        'selling_price': 200,
        'data_quota_mb': 512,
        'validity_minutes': 120,
        'speed_limit_mbps': 2.0,
      };

      final price = NetworkPrice.fromJson(json);

      expect(price.dataQuotaLabel, '512 ميجابايت');
      expect(price.validityLabel, '2 ساعات');
    });
  });
}
