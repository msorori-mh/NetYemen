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
      expect(
        ScanMatcher.normalizeForMatching('  Yemen   Hotspot   '),
        'yemen-hotspot',
      );
      expect(ScanMatcher.normalizeForMatching('YemenNet_5G'), 'yemennet_5g');
    });

    test(
      'matchSsidsToNetworks returns matched network and unmatched ssids',
      () {
        final result = ScanMatcher.matchSsidsToNetworks(
          scannedSsids: ['YemenNet_5G', 'UnknownNet'],
          networks: const [network],
        );

        expect(result.matchedNetworks, [network]);
        expect(result.unmatchedSsids, ['UnknownNet']);
      },
    );

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

    test('normalizeForMatching applies Unicode NFC normalization', () {
      // Decomposed "É" (E + combining acute) and pre-composed "É".
      const decomposed = 'E\u0301';
      const composed = '\u00C9';

      expect(
        ScanMatcher.normalizeForMatching(decomposed),
        ScanMatcher.normalizeForMatching(composed),
      );
    });

    test('normalizeForMatching collapses internal whitespace and hyphens', () {
      expect(
        ScanMatcher.normalizeForMatching('  Yemen   Hotspot   '),
        'yemen-hotspot',
      );
      expect(
        ScanMatcher.normalizeForMatching('Yemen---Hotspot'),
        'yemen-hotspot',
      );
      expect(
        ScanMatcher.normalizeForMatching('-Yemen-Hotspot-'),
        'yemen-hotspot',
      );
    });

    group('Unicode whitespace contract', () {
      test('collapses no-break space (U+00A0)', () {
        const input = 'Yemen\u00A0Hotspot';
        expect(ScanMatcher.normalizeForMatching(input), 'yemen-hotspot');
      });

      test('collapses narrow no-break space (U+202F)', () {
        const input = 'Yemen\u202FHotspot';
        expect(ScanMatcher.normalizeForMatching(input), 'yemen-hotspot');
      });

      test('collapses ideographic space (U+3000)', () {
        const input = 'Yemen\u3000Hotspot';
        expect(ScanMatcher.normalizeForMatching(input), 'yemen-hotspot');
      });

      test('collapses U+2000 through U+200A spaces', () {
        for (var code = 0x2000; code <= 0x200A; code++) {
          final input = 'Yemen${String.fromCharCode(code)}Hotspot';
          expect(
            ScanMatcher.normalizeForMatching(input),
            'yemen-hotspot',
            reason: 'U+${code.toRadixString(16).toUpperCase()} should collapse',
          );
        }
      });

      test('trims Unicode whitespace including NBSP', () {
        const input = '\u00A0\u00A0Yemen Hotspot\u00A0\u00A0';
        expect(ScanMatcher.normalizeForMatching(input), 'yemen-hotspot');
      });

      test('preserves Arabic content and applies NFC normalization', () {
        // Decomposed ALEF WITH HAMZA ABOVE vs pre-composed.
        const decomposed = '\u0623\u0645\u0627\u0646\u0629';
        const composed = '\u0623\u0645\u0627\u0646\u0629';
        expect(
          ScanMatcher.normalizeForMatching(decomposed),
          ScanMatcher.normalizeForMatching(composed),
        );
      });

      test('empty string when input is only Unicode whitespace', () {
        expect(ScanMatcher.normalizeForMatching('\u00A0\u2000\u3000'), '');
      });
    });
  });
}
