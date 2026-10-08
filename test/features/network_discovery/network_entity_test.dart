import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/features/network_discovery/domain/entities.dart';
import 'package:netyemen/features/network_discovery/domain/network_search.dart';

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

    test('matches multi-word queries regardless of spacing and case', () {
      const aden = NetworkEntity(
        id: 'network-3',
        commercialName: 'شبكة عدن للاتصالات',
        governorate: 'عدن',
        city: 'كريتر',
        ssidAliases: [
          SsidAlias(
            id: 'alias-3',
            networkId: 'network-3',
            ssidDisplay: 'Aden Connect',
            ssidNormalized: 'aden-connect',
          ),
        ],
      );

      expect(aden.matchesSearch('شبكة عدن'), isTrue);
      expect(aden.matchesSearch('  شبكة   عدن  '), isTrue);
      expect(aden.matchesSearch('عدن للاتصالات'), isTrue);
      expect(aden.matchesSearch('Aden Connect'), isTrue);
      expect(aden.matchesSearch('ADEN connect'), isTrue);
      expect(aden.matchesSearch('aden-connect'), isTrue);
      expect(aden.matchesSearch('شبكة تعز'), isFalse);
      expect(aden.matchesSearch(''), isTrue);
    });

    test('normalizeForSearch keeps words separated by a single space', () {
      expect(normalizeForSearch('  Yemen   NET '), 'yemen net');
      expect(normalizeForSearch('شبكة\u00A0عدن'), 'شبكة عدن');
      expect(normalizeForSearch('   '), '');
    });
  });
}
