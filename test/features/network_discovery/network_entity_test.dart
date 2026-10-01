import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/features/network_discovery/domain/entities.dart';

void main() {
  group('NetworkEntity', () {
    const network = NetworkEntity(
      id: 'network-1',
      commercialName: 'واصل نت',
      governorate: 'أمانة العاصمة',
      city: 'صنعاء',
      district: 'الوحدة',
      ssidAliases: [
        SsidAlias(
          id: 'alias-1',
          networkId: 'network-1',
          ssidDisplay: 'Wasel WiFi',
          ssidNormalized: 'wasel-wifi',
        ),
      ],
    );

    test('builds customer location text from available parts', () {
      expect(network.locationText, 'أمانة العاصمة - صنعاء - الوحدة');

      const partial = NetworkEntity(
        id: 'network-2',
        commercialName: 'شبكة تجريبية',
        governorate: 'عدن',
      );
      expect(partial.locationText, 'عدن');
    });

    test('matches customer search across name, location, and SSID', () {
      expect(network.matchesSearch('واصل'), isTrue);
      expect(network.matchesSearch('صنعاء'), isTrue);
      expect(network.matchesSearch('الوحدة'), isTrue);
      expect(network.matchesSearch('wasel-wifi'), isTrue);
      expect(network.matchesSearch('غير موجود'), isFalse);
    });
  });
}
