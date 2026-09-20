// lib/models/owned_network_model.dart

/// شبكة يملكها المستخدم الحالي، كما تعيدها `get_owned_networks()`.
///
/// الدالة تُعيد فقط الشبكات التي يملكها المستخدم فعلاً (عضوية `owner` نشطة
/// + دور `network_owner`) — لا حاجة لفلترة إضافية على العميل.
class OwnedNetwork {
  final String id;
  final String commercialName;
  final String? description;
  final String? governorate;
  final String? city;
  final String? district;

  /// إحدى: pending_approval | active | suspended | rejected
  final String status;

  /// إحدى: unverified | verified | rejected
  final String verificationStatus;

  const OwnedNetwork({
    required this.id,
    required this.commercialName,
    this.description,
    this.governorate,
    this.city,
    this.district,
    this.status = 'pending_approval',
    this.verificationStatus = 'unverified',
  });

  factory OwnedNetwork.fromJson(Map<String, dynamic> json) {
    return OwnedNetwork(
      id: json['id'] ?? '',
      commercialName: json['commercial_name'] ?? '',
      description: json['description'],
      governorate: json['governorate'],
      city: json['city'],
      district: json['district'],
      status: json['status'] ?? 'pending_approval',
      verificationStatus: json['verification_status'] ?? 'unverified',
    );
  }

  bool get isVerified => verificationStatus == 'verified';
  bool get isActive => status == 'active';

  /// نص الموقع (محافظة، مدينة) مع تخطي الأجزاء الناقصة بدل ترك فواصل فارغة.
  String get locationText {
    final parts = [governorate, city].where((p) => p != null && p.isNotEmpty);
    return parts.join('، ');
  }
}
