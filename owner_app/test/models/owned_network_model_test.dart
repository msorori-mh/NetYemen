import 'package:flutter_test/flutter_test.dart';
import 'package:owner/models/owned_network_model.dart';

void main() {
  group('OwnedNetwork', () {
    test('parses a row shaped like get_owned_networks()\'s return table', () {
      final network = OwnedNetwork.fromJson({
        'id': 'net-1',
        'commercial_name': 'شبكة النور',
        'description': 'شبكة حي النور',
        'governorate': 'صنعاء',
        'city': 'صنعاء',
        'district': 'شارع الستين',
        'status': 'active',
        'verification_status': 'verified',
      });

      expect(network.id, 'net-1');
      expect(network.commercialName, 'شبكة النور');
      expect(network.isActive, isTrue);
      expect(network.isVerified, isTrue);
      expect(network.locationText, 'صنعاء، صنعاء');
    });

    test('falls back to pending/unverified defaults when fields are absent', () {
      final network = OwnedNetwork.fromJson({
        'id': 'net-2',
        'commercial_name': 'شبكة تجريبية',
      });

      expect(network.status, 'pending_approval');
      expect(network.verificationStatus, 'unverified');
      expect(network.isActive, isFalse);
      expect(network.isVerified, isFalse);
      expect(network.locationText, isEmpty);
    });

    test('locationText skips a missing city instead of leaving a stray separator', () {
      final network = OwnedNetwork.fromJson({
        'id': 'net-3',
        'commercial_name': 'شبكة',
        'governorate': 'عدن',
      });

      expect(network.locationText, 'عدن');
    });
  });
}
