class CustomerProfile {
  final String id;
  final String? fullName;
  final String? governorate;
  final String? city;
  final bool isActive;
  final DateTime? createdAt;

  const CustomerProfile({
    required this.id,
    this.fullName,
    this.governorate,
    this.city,
    this.isActive = true,
    this.createdAt,
  });

  factory CustomerProfile.fromJson(Map<String, dynamic> json) {
    return CustomerProfile(
      id: json['id'] as String? ?? '',
      fullName: json['full_name'] as String?,
      governorate: json['default_governorate'] as String?,
      city: json['default_city'] as String?,
      isActive: json['account_status'] == 'active',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }
}

class CustomerProfileUpdate {
  final String fullName;
  final String governorate;
  final String city;

  const CustomerProfileUpdate({
    required this.fullName,
    required this.governorate,
    required this.city,
  });

  Map<String, String> toJson() => {
        'full_name': fullName.trim(),
        'default_governorate': governorate.trim(),
        'default_city': city.trim(),
      };
}
