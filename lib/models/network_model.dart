// lib/models/network_model.dart
class Network {
  final String id;
  final String? ownerId;
  final String name;
  final String? description;
  final String governorate;
  final String? district;
  final String? city;
  final String? locationText;
  final double? lat;
  final double? lng;
  final bool isApproved;
  final bool isActive;
  final bool isFeatured;
  final bool verifiedBadge;
  final List<String> ssids;
  final DateTime? createdAt;

  Network({
    required this.id,
    this.ownerId,
    required this.name,
    this.description,
    required this.governorate,
    this.district,
    this.city,
    this.locationText,
    this.lat,
    this.lng,
    this.isApproved = false,
    this.isActive = false,
    this.isFeatured = false,
    this.verifiedBadge = false,
    this.ssids = const [],
    this.createdAt,
  });

  factory Network.fromJson(Map<String, dynamic> json) {
    return Network(
      id: json['id'] ?? '',
      ownerId: json['owner_id'],
      name: json['name'] ?? '',
      description: json['description'],
      governorate: json['governorate'] ?? '',
      district: json['district'],
      city: json['city'],
      locationText: json['location_text'],
      lat: json['lat'] != null ? (json['lat'] as num).toDouble() : null,
      lng: json['lng'] != null ? (json['lng'] as num).toDouble() : null,
      isApproved: json['is_approved'] ?? false,
      isActive: json['is_active'] ?? false,
      isFeatured: json['is_featured'] ?? false,
      verifiedBadge: json['verified_badge'] ?? false,
      // network_ssids is fetched via a separate embedded select
      // (network_ssids(ssid)) — see SupabaseService.getNetworks.
      ssids: json['network_ssids'] != null
          ? (json['network_ssids'] as List)
              .map((row) => row['ssid'] as String)
              .toList()
          : const [],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
    );
  }

  String get displayLocation {
    if (locationText != null && locationText!.isNotEmpty) return locationText!;
    final parts = [governorate, if (city != null) city!].where((p) => p.isNotEmpty);
    return parts.join(' - ');
  }
}

class NetworkPrice {
  final String id;
  final String networkId;
  final int denomination;
  final int sellingPrice;
  final int dataQuotaMb;
  final int validityMinutes;
  final double speedLimitMbps;
  final bool isActive;

  NetworkPrice({
    required this.id,
    required this.networkId,
    required this.denomination,
    required this.sellingPrice,
    required this.dataQuotaMb,
    required this.validityMinutes,
    required this.speedLimitMbps,
    this.isActive = true,
  });

  factory NetworkPrice.fromJson(Map<String, dynamic> json) {
    return NetworkPrice(
      id: json['id'] ?? '',
      networkId: json['network_id'] ?? '',
      denomination: json['denomination'] ?? 0,
      sellingPrice: json['selling_price'] ?? 0,
      dataQuotaMb: json['data_quota_mb'] ?? 0,
      validityMinutes: json['validity_minutes'] ?? 0,
      speedLimitMbps: json['speed_limit_mbps'] != null
          ? (json['speed_limit_mbps'] as num).toDouble()
          : 0,
      isActive: json['is_active'] ?? true,
    );
  }

  String get validityLabel {
    if (validityMinutes % (24 * 60) == 0) {
      final days = validityMinutes ~/ (24 * 60);
      return '$days ${days == 1 ? 'يوم' : 'أيام'}';
    }
    if (validityMinutes % 60 == 0) {
      final hours = validityMinutes ~/ 60;
      return '$hours ${hours == 1 ? 'ساعة' : 'ساعات'}';
    }
    return '$validityMinutes دقيقة';
  }

  String get dataQuotaLabel {
    if (dataQuotaMb >= 1024 && dataQuotaMb % 1024 == 0) {
      return '${dataQuotaMb ~/ 1024} جيجابايت';
    }
    return '$dataQuotaMb ميجابايت';
  }
}
