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

  /// Mirrors [public.normalize_ssid] so Dart matching uses the same contract
  /// as the database: trim, Unicode NFC normalization, lowercase, collapse
  /// whitespace to hyphens, collapse hyphens, then trim surrounding hyphens.
  static String normalizeForMatching(String ssid) {
    var normalized = ssid.trim();
    normalized = nfc(normalized);
    normalized = normalized.toLowerCase();
    normalized = normalized.replaceAll(RegExp(r'\s+'), '-');
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
