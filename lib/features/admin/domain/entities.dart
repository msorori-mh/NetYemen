// lib/features/admin/domain/entities.dart
// Admin operations domain models for the NetYemen V1 pilot.

class AdminDashboardKpi {
  final int activeNetworks;
  final int pendingRequests;
  final int approvedRequests;
  final int rejectedRequests;
  final int activePackages;
  final int outOfStockPackages;
  final int networkOwners;
  final int networkOperators;

  const AdminDashboardKpi({
    required this.activeNetworks,
    required this.pendingRequests,
    required this.approvedRequests,
    required this.rejectedRequests,
    required this.activePackages,
    required this.outOfStockPackages,
    required this.networkOwners,
    required this.networkOperators,
  });

  factory AdminDashboardKpi.fromJson(Map<String, dynamic> json) {
    return AdminDashboardKpi(
      activeNetworks: (json['active_networks'] as num?)?.toInt() ?? 0,
      pendingRequests: (json['pending_requests'] as num?)?.toInt() ?? 0,
      approvedRequests: (json['approved_requests'] as num?)?.toInt() ?? 0,
      rejectedRequests: (json['rejected_requests'] as num?)?.toInt() ?? 0,
      activePackages: (json['active_packages'] as num?)?.toInt() ?? 0,
      outOfStockPackages: (json['out_of_stock_packages'] as num?)?.toInt() ?? 0,
      networkOwners: (json['network_owners'] as num?)?.toInt() ?? 0,
      networkOperators: (json['network_operators'] as num?)?.toInt() ?? 0,
    );
  }
}

class AdminNetworkRequest {
  final String id;
  final String requesterUserId;
  final String? idempotencyKey;
  final String? proposedNetworkName;
  final String observedSsidDisplay;
  final String? observedSsidNormalized;
  final String? governorate;
  final String? city;
  final String? district;
  final String? notes;
  final String status;
  final String? duplicateOf;
  final String? matchedNetworkId;
  final String? resolutionNote;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? resolvedAt;
  final String? resolvedBy;
  final String? requesterName;
  final String? matchedNetworkName;
  final String? matchedNetworkStatus;
  final String? matchedNetworkVerificationStatus;

  const AdminNetworkRequest({
    required this.id,
    required this.requesterUserId,
    this.idempotencyKey,
    this.proposedNetworkName,
    required this.observedSsidDisplay,
    this.observedSsidNormalized,
    this.governorate,
    this.city,
    this.district,
    this.notes,
    required this.status,
    this.duplicateOf,
    this.matchedNetworkId,
    this.resolutionNote,
    required this.createdAt,
    this.updatedAt,
    this.resolvedAt,
    this.resolvedBy,
    this.requesterName,
    this.matchedNetworkName,
    this.matchedNetworkStatus,
    this.matchedNetworkVerificationStatus,
  });

  factory AdminNetworkRequest.fromJson(Map<String, dynamic> json) {
    final requester = json['profiles'] as Map<String, dynamic>?;
    final matchedNetwork = json['networks'] as Map<String, dynamic>?;

    return AdminNetworkRequest(
      id: json['id'] as String? ?? '',
      requesterUserId: json['requester_user_id'] as String? ?? '',
      idempotencyKey: json['idempotency_key'] as String?,
      proposedNetworkName: json['proposed_network_name'] as String?,
      observedSsidDisplay: json['observed_ssid_display'] as String? ?? '',
      observedSsidNormalized: json['observed_ssid_normalized'] as String?,
      governorate: json['governorate'] as String?,
      city: json['city'] as String?,
      district: json['district'] as String?,
      notes: json['notes'] as String?,
      status: json['status'] as String? ?? 'submitted',
      duplicateOf: json['duplicate_of'] as String?,
      matchedNetworkId: json['matched_network_id'] as String?,
      resolutionNote: json['resolution_note'] as String?,
      createdAt: _parseDateTime(json['created_at']),
      updatedAt: _parseOptionalDateTime(json['updated_at']),
      resolvedAt: _parseOptionalDateTime(json['resolved_at']),
      resolvedBy: json['resolved_by'] as String?,
      requesterName: requester?['full_name'] as String?,
      matchedNetworkName: matchedNetwork?['commercial_name'] as String?,
      matchedNetworkStatus: matchedNetwork?['status'] as String?,
      matchedNetworkVerificationStatus:
          matchedNetwork?['verification_status'] as String?,
    );
  }

  bool get isTerminal =>
      status == 'approved' ||
      status == 'rejected' ||
      status == 'matched_existing';

  String get statusLabel => _networkRequestStatusLabel(status);
}

class AdminNetwork {
  final String id;
  final String commercialName;
  final String? description;
  final String? governorate;
  final String? city;
  final String? district;
  final String status;
  final String verificationStatus;
  final String? createdBy;
  final String? approvedBy;
  final DateTime? approvedAt;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final List<String> ownerNames;

  const AdminNetwork({
    required this.id,
    required this.commercialName,
    this.description,
    this.governorate,
    this.city,
    this.district,
    required this.status,
    required this.verificationStatus,
    this.createdBy,
    this.approvedBy,
    this.approvedAt,
    required this.createdAt,
    this.updatedAt,
    this.ownerNames = const [],
  });

  factory AdminNetwork.fromJson(Map<String, dynamic> json) {
    final memberships = json['network_memberships'] as List<dynamic>?;
    final owners = <String>[];
    if (memberships != null) {
      for (final item in memberships) {
        final membership = item as Map<String, dynamic>;
        if (membership['membership_role'] == 'owner') {
          final profile = membership['profiles'] as Map<String, dynamic>?;
          final name = profile?['full_name'] as String?;
          if (name != null && name.isNotEmpty) {
            owners.add(name);
          }
        }
      }
    }

    return AdminNetwork(
      id: json['id'] as String? ?? '',
      commercialName: json['commercial_name'] as String? ?? '',
      description: json['description'] as String?,
      governorate: json['governorate'] as String?,
      city: json['city'] as String?,
      district: json['district'] as String?,
      status: json['status'] as String? ?? 'pending_approval',
      verificationStatus:
          json['verification_status'] as String? ?? 'unverified',
      createdBy: json['created_by'] as String?,
      approvedBy: json['approved_by'] as String?,
      approvedAt: _parseOptionalDateTime(json['approved_at']),
      createdAt: _parseDateTime(json['created_at']),
      updatedAt: _parseOptionalDateTime(json['updated_at']),
      ownerNames: owners,
    );
  }

  String get statusLabel => _networkStatusLabel(status);

  String get verificationStatusLabel =>
      _verificationStatusLabel(verificationStatus);

  bool get isAdminActionable =>
      status == 'pending_approval' || status == 'suspended';

  String get locationText {
    final parts = <String>[
      if (governorate != null && governorate!.isNotEmpty) governorate!,
      if (city != null && city!.isNotEmpty) city!,
      if (district != null && district!.isNotEmpty) district!,
    ];
    return parts.join(' - ');
  }
}

class AdminSsidAlias {
  final String id;
  final String networkId;
  final String ssidDisplay;
  final String? ssidNormalized;
  final String status;
  final DateTime? verifiedAt;
  final String? verifiedBy;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const AdminSsidAlias({
    required this.id,
    required this.networkId,
    required this.ssidDisplay,
    this.ssidNormalized,
    required this.status,
    this.verifiedAt,
    this.verifiedBy,
    required this.createdAt,
    this.updatedAt,
  });

  factory AdminSsidAlias.fromJson(Map<String, dynamic> json) {
    return AdminSsidAlias(
      id: json['id'] as String? ?? '',
      networkId: json['network_id'] as String? ?? '',
      ssidDisplay: json['ssid_display'] as String? ?? '',
      ssidNormalized: json['ssid_normalized'] as String?,
      status: json['status'] as String? ?? 'pending_verification',
      verifiedAt: _parseOptionalDateTime(json['verified_at']),
      verifiedBy: json['verified_by'] as String?,
      createdAt: _parseDateTime(json['created_at']),
      updatedAt: _parseOptionalDateTime(json['updated_at']),
    );
  }

  String get statusLabel => _aliasStatusLabel(status);

  bool get isPending => status == 'pending_verification';
}

class AdminPackageInventory {
  final String id;
  final String networkId;
  final String name;
  final String? description;
  final int price;
  final String currency;
  final int? durationValue;
  final String? durationUnit;
  final int? speedMbps;
  final String packageType;
  final String status;
  final bool isPublic;
  final int sortOrder;
  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int totalUnits;
  final int availableUnits;

  const AdminPackageInventory({
    required this.id,
    required this.networkId,
    required this.name,
    this.description,
    required this.price,
    required this.currency,
    this.durationValue,
    this.durationUnit,
    this.speedMbps,
    required this.packageType,
    required this.status,
    required this.isPublic,
    required this.sortOrder,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
    required this.totalUnits,
    required this.availableUnits,
  });

  factory AdminPackageInventory.fromJson(Map<String, dynamic> json) {
    final balance = json['package_inventory_balances'] as List<dynamic>?;
    final firstBalance = balance?.isNotEmpty == true
        ? balance!.first as Map<String, dynamic>
        : null;

    return AdminPackageInventory(
      id: json['id'] as String? ?? '',
      networkId: json['network_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      price: (json['price'] as num?)?.toInt() ?? 0,
      currency: json['currency'] as String? ?? 'YER',
      durationValue: (json['duration_value'] as num?)?.toInt(),
      durationUnit: json['duration_unit'] as String?,
      speedMbps: (json['speed_mbps'] as num?)?.toInt(),
      packageType: json['package_type'] as String? ?? 'time',
      status: json['status'] as String? ?? 'draft',
      isPublic: json['is_public'] as bool? ?? false,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      createdBy: json['created_by'] as String?,
      createdAt: _parseOptionalDateTime(json['created_at']),
      updatedAt: _parseOptionalDateTime(json['updated_at']),
      totalUnits: (firstBalance?['total_units'] as num?)?.toInt() ?? 0,
      availableUnits: (firstBalance?['available_units'] as num?)?.toInt() ?? 0,
    );
  }

  bool get isOutOfStock => availableUnits <= 0;

  String get displayPrice {
    final value = price / 100;
    final rounded = value == value.toInt() ? value.toInt() : value;
    return '$rounded $currency';
  }

  String get durationText {
    if (durationValue == null || durationUnit == null || durationValue == 0) {
      return '';
    }
    final unit = _durationUnitLabel(durationUnit!);
    return '$durationValue $unit';
  }
}

class AdminUser {
  final String id;
  final String? fullName;
  final String accountStatus;
  final List<String> roles;

  const AdminUser({
    required this.id,
    this.fullName,
    required this.accountStatus,
    this.roles = const [],
  });

  factory AdminUser.fromJson(Map<String, dynamic> json) {
    final rolesJson = json['user_roles'] as List<dynamic>?;
    final roles =
        rolesJson
            ?.map((r) => (r as Map<String, dynamic>)['role'] as String?)
            .whereType<String>()
            .toList() ??
        <String>[];

    return AdminUser(
      id: json['id'] as String? ?? '',
      fullName: json['full_name'] as String?,
      accountStatus: json['account_status'] as String? ?? 'active',
      roles: roles,
    );
  }

  String get displayName =>
      fullName?.isNotEmpty == true ? fullName! : 'مستخدم $id';
}

class AdminNetworkMembership {
  final String networkId;
  final String userId;
  final String membershipRole;
  final String status;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? createdBy;
  final String? fullName;

  const AdminNetworkMembership({
    required this.networkId,
    required this.userId,
    required this.membershipRole,
    required this.status,
    required this.createdAt,
    this.updatedAt,
    this.createdBy,
    this.fullName,
  });

  factory AdminNetworkMembership.fromJson(Map<String, dynamic> json) {
    final profile = json['profiles'] as Map<String, dynamic>?;

    return AdminNetworkMembership(
      networkId: json['network_id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      membershipRole: json['membership_role'] as String? ?? 'operator',
      status: json['status'] as String? ?? 'active',
      createdAt: _parseDateTime(json['created_at']),
      updatedAt: _parseOptionalDateTime(json['updated_at']),
      createdBy: json['created_by'] as String?,
      fullName: profile?['full_name'] as String?,
    );
  }

  String get roleLabel => membershipRole == 'owner' ? 'مالك' : 'مشغّل';
}

class AdminAuditEvent {
  final String id;
  final DateTime occurredAt;
  final String? actorUserId;
  final String? actorRole;
  final String action;
  final String entityType;
  final String? entityId;
  final String result;
  final String? reasonCode;
  final Map<String, dynamic> metadata;
  final String? correlationId;

  const AdminAuditEvent({
    required this.id,
    required this.occurredAt,
    this.actorUserId,
    this.actorRole,
    required this.action,
    required this.entityType,
    this.entityId,
    required this.result,
    this.reasonCode,
    this.metadata = const {},
    this.correlationId,
  });

  factory AdminAuditEvent.fromJson(Map<String, dynamic> json) {
    return AdminAuditEvent(
      id: json['id'] as String? ?? '',
      occurredAt: _parseDateTime(json['occurred_at']),
      actorUserId: json['actor_user_id'] as String?,
      actorRole: json['actor_role'] as String?,
      action: json['action'] as String? ?? '',
      entityType: json['entity_type'] as String? ?? '',
      entityId: json['entity_id'] as String?,
      result: json['result'] as String? ?? 'success',
      reasonCode: json['reason_code'] as String?,
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? const {},
      correlationId: json['correlation_id'] as String?,
    );
  }
}

// ---------------------------------------------------------------------------
// Parsing helpers
// ---------------------------------------------------------------------------

DateTime _parseDateTime(dynamic value) {
  if (value == null) return DateTime.now();
  if (value is DateTime) return value;
  return DateTime.parse(value as String);
}

DateTime? _parseOptionalDateTime(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.parse(value as String);
}

// ---------------------------------------------------------------------------
// Status label helpers
// ---------------------------------------------------------------------------

String _networkRequestStatusLabel(String status) {
  switch (status) {
    case 'submitted':
      return 'قيد الإرسال';
    case 'under_review':
      return 'قيد المراجعة';
    case 'matched_existing':
      return 'مطابق مع شبكة موجودة';
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

String _networkStatusLabel(String status) {
  switch (status) {
    case 'pending_approval':
      return 'في انتظار الموافقة';
    case 'active':
      return 'نشطة';
    case 'suspended':
      return 'معلّقة';
    case 'rejected':
      return 'مرفوضة';
    default:
      return status;
  }
}

String _verificationStatusLabel(String status) {
  switch (status) {
    case 'unverified':
      return 'غير موثّقة';
    case 'verified':
      return 'موثّقة';
    case 'rejected':
      return 'مرفوضة';
    default:
      return status;
  }
}

String _aliasStatusLabel(String status) {
  switch (status) {
    case 'pending_verification':
      return 'في انتظار التوثيق';
    case 'active':
      return 'نشطة';
    case 'suspended':
      return 'معلّقة';
    case 'rejected':
      return 'مرفوضة';
    default:
      return status;
  }
}

String _durationUnitLabel(String unit) {
  switch (unit) {
    case 'hour':
      return 'ساعة';
    case 'day':
      return 'يوم';
    case 'week':
      return 'أسبوع';
    case 'month':
      return 'شهر';
    default:
      return unit;
  }
}
