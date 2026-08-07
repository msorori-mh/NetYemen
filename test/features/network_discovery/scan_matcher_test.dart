import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/features/network_discovery/data/scan_matcher.dart';
import 'package:netyemen/features/network_discovery/domain/entities.dart';

void main() {
  group('ScanMatcher', () {
    const network = NetworkEntity(
      id: 'net-1',
      commercialName: 'Yemen Net',
      governorate: 'Sanaa',
      city: 'Sanaa City',
      ssidAliases: [
        SsidAlias(
          id: 'alias-1',
          networkId: 'net-1',
          ssidDisplay: 'YemenNet_5G',
          ssidNormalized: 'yemennet-5g',
        ),
      ],
    );

    test('deduplicateSsids removes empty, unknown and duplicate values', () {
      final input = [
        'YemenNet_5G',
        '  YemenNet_5G ',
        '<unknown ssid>',
        '',
        'OtherNet',
        'othernet',
      ];
      final result = ScanMatcher.deduplicateSsids(input);
      expect(result, ['YemenNet_5G', 'OtherNet']);
    });

    test('normalizeForMatching lowercases and replaces whitespace', () {
      expect(ScanMatcher.normalizeForMatching('  Yemen   Hotspot   '),
          'yemen-hotspot');
      expect(ScanMatcher.normalizeForMatching('YemenNet_5G'), 'yemennet_5g');
    });

    test('matchSsidsToNetworks returns matched network and unmatched ssids',
        () {
      final result = ScanMatcher.matchSsidsToNetworks(
        scannedSsids: ['YemenNet_5G', 'UnknownNet'],
        networks: const [network],
      );

      expect(result.matchedNetworks, [network]);
      expect(result.unmatchedSsids, ['UnknownNet']);
    });

    test('matchSsidsToNetworks matches by display name ignoring case', () {
      final result = ScanMatcher.matchSsidsToNetworks(
        scannedSsids: ['yemennet_5g'],
        networks: const [network],
      );

      expect(result.matchedNetworks, [network]);
      expect(result.unmatchedSsids, isEmpty);
    });

    test('matchSsidsToNetworks does not match the same network twice', () {
      final result = ScanMatcher.matchSsidsToNetworks(
        scannedSsids: ['YemenNet_5G', 'YemenNet_5G'],
        networks: const [network],
      );

      expect(result.matchedNetworks, [network]);
      expect(result.unmatchedSsids, isEmpty);
    });
  });
}
