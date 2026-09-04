// lib/models/user_model.dart
class AppUser {
  final String id;
  final String phone;
  final String? fullName;
  final String role;
  final String status;
  final bool isIdentityVerified;
  final DateTime? createdAt;

  const AppUser({
    required this.id,
    required this.phone,
    this.fullName,
    this.role = 'customer',
    this.status = 'active',
    this.isIdentityVerified = false,
    this.createdAt,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] ?? '',
      phone: json['phone'] ?? '',
      fullName: json['full_name'],
      role: json['role'] ?? 'customer',
      status: json['status'] ?? 'active',
      isIdentityVerified: json['is_identity_verified'] ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
    );
  }

  bool get isActive => status == 'active';
}
