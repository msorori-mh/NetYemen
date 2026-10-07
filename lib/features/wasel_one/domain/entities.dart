class FederatedAccessPlan {
  final String id;
  final String name;
  final String? description;
  final int retailPrice;
  final String currency;
  final int validitySeconds;
  final int? quotaBytes;
  final int? speedLimitKbps;
  final int maxConcurrentSessions;
  final int partnerCount;

  const FederatedAccessPlan({
    required this.id,
    required this.name,
    this.description,
    required this.retailPrice,
    required this.currency,
    required this.validitySeconds,
    this.quotaBytes,
    this.speedLimitKbps,
    required this.maxConcurrentSessions,
    required this.partnerCount,
  });

  factory FederatedAccessPlan.fromJson(Map<String, dynamic> json) {
    final partnerRows = json['federated_plan_networks'];
    var partnerCount = 0;
    if (partnerRows is List && partnerRows.isNotEmpty) {
      final first = partnerRows.first;
      if (first is Map) partnerCount = (first['count'] as num?)?.toInt() ?? 0;
    }
    return FederatedAccessPlan(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      retailPrice: (json['retail_price'] as num?)?.toInt() ?? 0,
      currency: json['currency'] as String? ?? 'YER',
      validitySeconds: (json['validity_seconds'] as num?)?.toInt() ?? 0,
      quotaBytes: (json['quota_bytes'] as num?)?.toInt(),
      speedLimitKbps: (json['speed_limit_kbps'] as num?)?.toInt(),
      maxConcurrentSessions:
          (json['max_concurrent_sessions'] as num?)?.toInt() ?? 1,
      partnerCount: partnerCount,
    );
  }

  Duration get validity => Duration(seconds: validitySeconds);
}

class AccessEntitlement {
  final String id;
  final String planId;
  final String planName;
  final String status;
  final DateTime startsAt;
  final DateTime expiresAt;
  final int? allowanceBytes;
  final int consumedBytes;
  final int? speedLimitKbps;
  final int maxConcurrentSessions;

  const AccessEntitlement({
    required this.id,
    required this.planId,
    required this.planName,
    required this.status,
    required this.startsAt,
    required this.expiresAt,
    this.allowanceBytes,
    required this.consumedBytes,
    this.speedLimitKbps,
    required this.maxConcurrentSessions,
  });

  factory AccessEntitlement.fromJson(Map<String, dynamic> json) {
    final plan = json['federated_access_plans'];
    final planJson = plan is Map
        ? Map<String, dynamic>.from(plan)
        : const <String, dynamic>{};
    return AccessEntitlement(
      id: json['id'] as String? ?? '',
      planId: json['plan_id'] as String? ?? '',
      planName: planJson['name'] as String? ?? 'باقة واصل ون',
      status: json['status'] as String? ?? 'pending',
      startsAt: DateTime.parse(json['starts_at'] as String),
      expiresAt: DateTime.parse(json['expires_at'] as String),
      allowanceBytes: (json['allowance_bytes'] as num?)?.toInt(),
      consumedBytes: (json['consumed_bytes'] as num?)?.toInt() ?? 0,
      speedLimitKbps: (json['speed_limit_kbps'] as num?)?.toInt(),
      maxConcurrentSessions:
          (json['max_concurrent_sessions'] as num?)?.toInt() ?? 1,
    );
  }

  int? get remainingBytes {
    final allowance = allowanceBytes;
    if (allowance == null) return null;
    return (allowance - consumedBytes).clamp(0, allowance).toInt();
  }

  bool get isUsable {
    final now = DateTime.now();
    return status == 'active' &&
        !startsAt.isAfter(now) &&
        expiresAt.isAfter(now);
  }
}

class RadiusAccessCredential {
  final String credentialId;
  final String username;
  final String password;
  final DateTime expiresAt;

  const RadiusAccessCredential({
    required this.credentialId,
    required this.username,
    required this.password,
    required this.expiresAt,
  });

  factory RadiusAccessCredential.fromJson(Map<String, dynamic> json) {
    return RadiusAccessCredential(
      credentialId: json['credential_id'] as String? ?? '',
      username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '',
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }
}

class WaselOnePurchaseResult {
  final String purchaseId;
  final String entitlementId;
  final String status;
  final int amountPaid;
  final String currency;
  final int newBalance;
  final DateTime? startsAt;
  final DateTime? expiresAt;
  final bool replayed;

  const WaselOnePurchaseResult({
    required this.purchaseId,
    required this.entitlementId,
    required this.status,
    required this.amountPaid,
    required this.currency,
    required this.newBalance,
    this.startsAt,
    this.expiresAt,
    required this.replayed,
  });

  factory WaselOnePurchaseResult.fromJson(Map<String, dynamic> json) {
    return WaselOnePurchaseResult(
      purchaseId: json['purchase_id'] as String? ?? '',
      entitlementId: json['entitlement_id'] as String? ?? '',
      status: json['status'] as String? ?? '',
      amountPaid: (json['amount_paid'] as num?)?.toInt() ?? 0,
      currency: json['currency'] as String? ?? 'YER',
      newBalance: (json['new_balance'] as num?)?.toInt() ?? 0,
      startsAt: _tryDate(json['starts_at']),
      expiresAt: _tryDate(json['expires_at']),
      replayed: json['replayed'] as bool? ?? false,
    );
  }

  bool get isCompleted => status == 'completed';
}

DateTime? _tryDate(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value);
}
