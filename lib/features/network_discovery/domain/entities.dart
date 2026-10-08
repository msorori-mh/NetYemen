import 'network_search.dart';

class NetworkEntity {
  final String id;
  final String commercialName;
  final String? description;
  final String? governorate;
  final String? city;
  final String? district;
  final List<SsidAlias> ssidAliases;

  const NetworkEntity({
    required this.id,
    required this.commercialName,
    this.description,
    this.governorate,
    this.city,
    this.district,
    this.ssidAliases = const [],
  });

  String get locationText {
    final parts = <String>[
      if (governorate != null && governorate!.isNotEmpty) governorate!,
      if (city != null && city!.isNotEmpty) city!,
      if (district != null && district!.isNotEmpty) district!,
    ];
    return parts.join(' - ');
  }

  /// Whether this network matches a customer search [query].
  ///
  /// The query and every searched field go through [normalizeForSearch], so
  /// case, Unicode form and spacing never decide the outcome.
  bool matchesSearch(String query) {
    final normalizedQuery = normalizeForSearch(query);
    if (normalizedQuery.isEmpty) {
      return true;
    }
    final fields = [commercialName, city, district, governorate];
    for (final field in fields) {
      if (field != null &&
          normalizeForSearch(field).contains(normalizedQuery)) {
        return true;
      }
    }
    // Stored SSIDs use hyphens where the customer may type spaces.
    final ssidQuery = normalizedQuery.replaceAll(' ', '-');
    return ssidAliases.any(
      (a) =>
          a.ssidNormalized.contains(ssidQuery) ||
          normalizeForSearch(a.ssidDisplay).contains(normalizedQuery),
    );
  }

  NetworkEntity copyWith({List<SsidAlias>? ssidAliases}) {
    return NetworkEntity(
      id: id,
      commercialName: commercialName,
      description: description,
      governorate: governorate,
      city: city,
      district: district,
      ssidAliases: ssidAliases ?? this.ssidAliases,
    );
  }
}

class SsidAlias {
  final String id;
  final String networkId;
  final String ssidDisplay;
  final String ssidNormalized;

  const SsidAlias({
    required this.id,
    required this.networkId,
    required this.ssidDisplay,
    required this.ssidNormalized,
  });
}

class ScanMatchResult {
  final List<NetworkEntity> matchedNetworks;
  final List<String> unmatchedSsids;

  const ScanMatchResult({
    this.matchedNetworks = const [],
    this.unmatchedSsids = const [],
  });
}
