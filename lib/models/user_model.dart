// lib/models/user_model.dart
class AppUser {
  final String id;
  final String phone;
  final String? fullName;
  final String role;
  final int walletBalance;
  final String? governorate;
  final String? city;
  final String? district;
  final bool isActive;
  final DateTime? createdAt;

  const AppUser({
    required this.id,
    required this.phone,
    this.fullName,
    this.role = 'customer',
    this.walletBalance = 0,
    this.governorate,
    this.city,
    this.district,
    this.isActive = true,
    this.createdAt,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] ?? '',
      phone: json['phone'] ?? '',
      fullName: json['full_name'],
      role: json['role'] ?? 'customer',
      walletBalance: json['wallet_balance'] ?? 0,
      governorate: json['governorate'],
      city: json['city'],
      district: json['district'],
      isActive: json['is_active'] ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'phone': phone,
      'full_name': fullName,
      'role': role,
      'wallet_balance': walletBalance,
      'governorate': governorate,
      'city': city,
      'district': district,
      'is_active': isActive,
    };
  }
}
