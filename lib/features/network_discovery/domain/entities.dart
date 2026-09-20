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

  bool matchesSearch(String normalizedQuery) {
    if (normalizedQuery.isEmpty) {
      return true;
    }
    if (commercialName.toLowerCase().contains(normalizedQuery)) {
      return true;
    }
    if ((city ?? '').toLowerCase().contains(normalizedQuery)) {
      return true;
    }
    if ((district ?? '').toLowerCase().contains(normalizedQuery)) {
      return true;
    }
    if ((governorate ?? '').toLowerCase().contains(normalizedQuery)) {
      return true;
    }
    return ssidAliases.any(
      (a) =>
          a.ssidNormalized.contains(normalizedQuery) ||
          a.ssidDisplay.toLowerCase().contains(normalizedQuery),
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
