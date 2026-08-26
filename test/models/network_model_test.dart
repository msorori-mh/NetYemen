import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/models/network_model.dart';

void main() {
  group('Network.fromJson', () {
    test(
      'correctly parses all fields including optional district and coordinates',
      () {
        final json = {
          'id': 'net-123',
          'owner_id': 'owner-456',
          'name': 'Yemen Net Fast',
          'ssid': 'YemenNet_WiFi',
          'governorate': 'Sana\'a',
          'city': 'Sana\'a City',
          'district': 'Al Wahdah',
          'phone': '770000000',
          'whatsapp': '770000000',
          'location_lat': 15.3694,
          'location_lng': 44.1910,
          'is_active': true,
          'is_featured': true,
          'created_at': '2026-01-01T00:00:00.000Z',
        };

        final network = Network.fromJson(json);

        expect(network.id, 'net-123');
        expect(network.ownerId, 'owner-456');
        expect(network.name, 'Yemen Net Fast');
        expect(network.ssid, 'YemenNet_WiFi');
        expect(network.governorate, 'Sana\'a');
        expect(network.city, 'Sana\'a City');
        expect(network.district, 'Al Wahdah');
        expect(network.phone, '770000000');
        expect(network.whatsapp, '770000000');
        expect(network.lat, 15.3694);
        expect(network.lng, 44.1910);
        expect(network.isActive, isTrue);
        expect(network.isFeatured, isTrue);
        expect(network.locationText, 'Sana\'a - Sana\'a City - Al Wahdah');
      },
    );

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
      expect(network.isActive, isTrue);
      expect(network.isFeatured, isFalse);
      expect(network.locationText, 'Aden - Crater');
    });
  });
}
