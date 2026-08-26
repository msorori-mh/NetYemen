class NetworkPackage {
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

  const NetworkPackage({
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
  });

  factory NetworkPackage.fromJson(Map<String, dynamic> json) {
    return NetworkPackage(
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
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  String get displayPrice {
    final value = price / 100;
    // Round to 2 decimals only if needed.
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

  bool get isAvailableForPublic => status == 'active' && isPublic;

  NetworkPackage copyWith({
    String? name,
    String? description,
    int? price,
    String? currency,
    int? durationValue,
    String? durationUnit,
    int? speedMbps,
    String? packageType,
    String? status,
    bool? isPublic,
    int? sortOrder,
  }) {
    return NetworkPackage(
      id: id,
      networkId: networkId,
      name: name ?? this.name,
      description: description ?? this.description,
      price: price ?? this.price,
      currency: currency ?? this.currency,
      durationValue: durationValue ?? this.durationValue,
      durationUnit: durationUnit ?? this.durationUnit,
      speedMbps: speedMbps ?? this.speedMbps,
      packageType: packageType ?? this.packageType,
      status: status ?? this.status,
      isPublic: isPublic ?? this.isPublic,
      sortOrder: sortOrder ?? this.sortOrder,
      createdBy: createdBy,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  static String _durationUnitLabel(String unit) {
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
}

class PackageInventoryBalance {
  final String packageId;
  final String networkId;
  final int totalUnits;
  final int availableUnits;
  final bool isAvailable;

  const PackageInventoryBalance({
    required this.packageId,
    required this.networkId,
    required this.totalUnits,
    required this.availableUnits,
    required this.isAvailable,
  });

  factory PackageInventoryBalance.fromJson(Map<String, dynamic> json) {
    return PackageInventoryBalance(
      packageId: json['package_id'] as String? ?? '',
      networkId: json['network_id'] as String? ?? '',
      totalUnits: (json['total_units'] as num?)?.toInt() ?? 0,
      availableUnits: (json['available_units'] as num?)?.toInt() ?? 0,
      isAvailable: json['is_available'] as bool? ?? true,
    );
  }

  bool get isOutOfStock => availableUnits <= 0;
}

class PackageInventoryMovement {
  final String id;
  final String packageId;
  final String networkId;
  final int quantityChange;
  final int previousTotal;
  final int newTotal;
  final int previousAvailable;
  final int newAvailable;
  final String reason;
  final String? actorUserId;
  final DateTime? createdAt;

  const PackageInventoryMovement({
    required this.id,
    required this.packageId,
    required this.networkId,
    required this.quantityChange,
    required this.previousTotal,
    required this.newTotal,
    required this.previousAvailable,
    required this.newAvailable,
    required this.reason,
    this.actorUserId,
    this.createdAt,
  });

  factory PackageInventoryMovement.fromJson(Map<String, dynamic> json) {
    return PackageInventoryMovement(
      id: json['id'] as String? ?? '',
      packageId: json['package_id'] as String? ?? '',
      networkId: json['network_id'] as String? ?? '',
      quantityChange: (json['quantity_change'] as num?)?.toInt() ?? 0,
      previousTotal: (json['previous_total'] as num?)?.toInt() ?? 0,
      newTotal: (json['new_total'] as num?)?.toInt() ?? 0,
      previousAvailable: (json['previous_available'] as num?)?.toInt() ?? 0,
      newAvailable: (json['new_available'] as num?)?.toInt() ?? 0,
      reason: json['reason'] as String? ?? '',
      actorUserId: json['actor_user_id'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }
}
