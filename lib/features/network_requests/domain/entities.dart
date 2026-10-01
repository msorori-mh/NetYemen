class NetworkAdditionRequest {
  final String id;
  final String status;
  final String observedSsidDisplay;
  final String? proposedNetworkName;
  final String? governorate;
  final String? city;
  final String? district;
  final String? notes;
  final String? resolutionNote;
  final String? matchedNetworkId;
  final DateTime createdAt;
  final DateTime? resolvedAt;

  const NetworkAdditionRequest({
    required this.id,
    required this.status,
    required this.observedSsidDisplay,
    this.proposedNetworkName,
    this.governorate,
    this.city,
    this.district,
    this.notes,
    this.resolutionNote,
    this.matchedNetworkId,
    required this.createdAt,
    this.resolvedAt,
  });

  factory NetworkAdditionRequest.fromJson(Map<String, dynamic> json) {
    return NetworkAdditionRequest(
      id: json['id'] as String,
      status: json['status'] as String,
      observedSsidDisplay: json['observed_ssid_display'] as String,
      proposedNetworkName: json['proposed_network_name'] as String?,
      governorate: json['governorate'] as String?,
      city: json['city'] as String?,
      district: json['district'] as String?,
      notes: json['notes'] as String?,
      resolutionNote: json['resolution_note'] as String?,
      matchedNetworkId: json['matched_network_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      resolvedAt: json['resolved_at'] != null
          ? DateTime.parse(json['resolved_at'] as String)
          : null,
    );
  }

  String get statusLabel {
    switch (status) {
      case 'submitted':
        return 'قيد الإرسال';
      case 'under_review':
        return 'قيد المراجعة';
      case 'matched_existing':
        return 'تمت مطابقته';
      case 'approved':
        return 'تمت الموافقة';
      case 'rejected':
        return 'مرفوض';
      case 'cancelled':
        return 'ملغي';
      default:
        return status;
    }
  }
}
