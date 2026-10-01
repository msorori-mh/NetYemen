import 'package:unorm_dart/unorm_dart.dart';

import '../domain/entities.dart';

class ScanMatcher {
  static List<String> deduplicateSsids(List<String> ssids) {
    final seen = <String>{};
    final result = <String>[];
    for (final ssid in ssids) {
      final trimmed = ssid.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed == '<unknown ssid>') continue;
      final lower = trimmed.toLowerCase();
      if (seen.contains(lower)) continue;
      seen.add(lower);
      result.add(trimmed);
    }
    return result;
  }

  // Explicit Unicode whitespace contract shared with PostgreSQL
  // public.normalize_ssid. Covers ASCII whitespace, U+0085 NEL, U+00A0 NBSP,
  // U+1680, U+2000-U+200A, U+2028/U+2029, U+202F, U+205F, and U+3000.
  static final _whitespaceSet = <int>[
    0x09,
    0x0A,
    0x0B,
    0x0C,
    0x0D,
    0x20,
    0x85,
    0xA0,
    0x1680,
    0x2000,
    0x2001,
    0x2002,
    0x2003,
    0x2004,
    0x2005,
    0x2006,
    0x2007,
    0x2008,
    0x2009,
    0x200A,
    0x2028,
    0x2029,
    0x202F,
    0x205F,
    0x3000,
  ].map((c) => String.fromCharCode(c)).join();

  static final _surroundingWhitespace = RegExp(
    '^[$_whitespaceSet]+|[$_whitespaceSet]+\$',
  );
  static final _internalWhitespace = RegExp('[$_whitespaceSet]+');

  /// Mirrors [public.normalize_ssid] so Dart matching uses the same contract
  /// as the database: trim defined Unicode whitespace, Unicode NFC
  /// normalization, lowercase, collapse whitespace to hyphens, collapse
  /// hyphens, then trim surrounding hyphens.
  static String normalizeForMatching(String ssid) {
    var normalized = ssid.replaceAll(_surroundingWhitespace, '');
    if (normalized.isEmpty) {
      return '';
    }
    normalized = nfc(normalized);
    normalized = normalized.toLowerCase();
    normalized = normalized.replaceAll(_internalWhitespace, '-');
    normalized = normalized.replaceAll(RegExp(r'-+'), '-');
    normalized = normalized.replaceAll(RegExp(r'^-+'), '');
    normalized = normalized.replaceAll(RegExp(r'-+$'), '');
    return normalized;
  }

  static ScanMatchResult matchSsidsToNetworks({
    required List<String> scannedSsids,
    required List<NetworkEntity> networks,
  }) {
    final deduped = deduplicateSsids(scannedSsids);
    final matchedNetworks = <NetworkEntity>[];
    final matchedNetworkIds = <String>{};
    final matchedSsidSet = <String>{};

    for (final ssid in deduped) {
      final normalized = normalizeForMatching(ssid);
      for (final network in networks) {
        if (matchedNetworkIds.contains(network.id)) continue;
        for (final alias in network.ssidAliases) {
          if (alias.ssidNormalized == normalized ||
              alias.ssidDisplay.toLowerCase() == ssid.toLowerCase()) {
            matchedNetworkIds.add(network.id);
            matchedSsidSet.add(ssid.toLowerCase());
            matchedNetworks.add(network);
            break;
          }
        }
        if (matchedNetworkIds.contains(network.id)) break;
      }
    }

    final unmatched = deduped
        .where((s) => !matchedSsidSet.contains(s.toLowerCase()))
        .toList();

    return ScanMatchResult(
      matchedNetworks: matchedNetworks,
      unmatchedSsids: unmatched,
    );
  }
}
