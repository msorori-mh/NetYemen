// lib/models/network_model.dart
class Network {
  final String id;
  final String? ownerId;
  final String name;
  final String? ssid;
  final String governorate;
  final String city;
  final String? district;
  final String? phone;
  final String? whatsapp;
  final double? lat;
  final double? lng;
  final bool isActive;
  final bool isFeatured;
  final DateTime? createdAt;

  Network({
    required this.id,
    this.ownerId,
    required this.name,
    this.ssid,
    required this.governorate,
    required this.city,
    this.district,
    this.phone,
    this.whatsapp,
    this.lat,
    this.lng,
    this.isActive = true,
    this.isFeatured = false,
    this.createdAt,
  });

  factory Network.fromJson(Map<String, dynamic> json) {
    return Network(
      id: json['id'] ?? '',
      ownerId: json['owner_id'],
      name: json['name'] ?? '',
      ssid: json['ssid'],
      governorate: json['governorate'] ?? '',
      city: json['city'] ?? '',
      district: json['district'],
      phone: json['phone'],
      whatsapp: json['whatsapp'],
      lat: json['location_lat'] != null 
          ? (json['location_lat'] as num).toDouble() 
          : null,
      lng: json['location_lng'] != null 
          ? (json['location_lng'] as num).toDouble() 
          : null,
      isActive: json['is_active'] ?? true,
      isFeatured: json['is_featured'] ?? false,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at']) 
          : null,
    );
  }

  String get locationText => '$governorate - $city${district != null ? ' - $district' : ''}';
}

class NetworkPrice {
  final String id;
  final String networkId;
  final int denomination;
  final int price;
  final bool isActive;

  NetworkPrice({
    required this.id,
    required this.networkId,
    required this.denomination,
    required this.price,
    this.isActive = true,
  });

  factory NetworkPrice.fromJson(Map<String, dynamic> json) {
    return NetworkPrice(
      id: json['id'] ?? '',
      networkId: json['network_id'] ?? '',
      denomination: json['denomination'] ?? 0,
      price: json['price'] ?? 0,
      isActive: json['is_active'] ?? true,
    );
  }
}
