// lib/features/purchase/domain/entities.dart

class PurchaseOrder {
  final String id;
  final String packageId;
  final String networkId;
  final String? networkName;
  final String? packageName;
  final int quantity;
  final int unitPrice;
  final int totalPrice;
  final String currency;
  final String status;
  final DateTime? createdAt;
  final int grossAmount;
  final double commissionRateSnapshot;
  final int commissionAmount;
  final int ownerNetAmount;

  const PurchaseOrder({
    required this.id,
    required this.packageId,
    required this.networkId,
    this.networkName,
    this.packageName,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
    required this.currency,
    required this.status,
    this.createdAt,
    required this.grossAmount,
    required this.commissionRateSnapshot,
    required this.commissionAmount,
    required this.ownerNetAmount,
  });

  factory PurchaseOrder.fromJson(Map<String, dynamic> json) {
    final gross = (json['gross_amount'] as num?)?.toInt() ??
        (json['total_price'] as num?)?.toInt() ??
        (json['amount_paid'] as num?)?.toInt() ??
        0;
    final commissionRate = (json['commission_rate_snapshot'] as num?)?.toDouble() ??
        ((json['commission_rate'] as num?)?.toDouble() ?? 0.03);
    final commission = (json['commission_amount'] as num?)?.toInt() ??
        (gross * commissionRate).floor();
    final net = (json['owner_net_amount'] as num?)?.toInt() ??
        (json['net_to_owner'] as num?)?.toInt() ??
        (gross - commission);

    return PurchaseOrder(
      id: json['id'] as String? ?? '',
      packageId: json['package_id'] as String? ?? '',
      networkId: json['network_id'] as String? ?? '',
      networkName: json['network_name'] as String? ??
          json['networks']?['name'] as String?,
      packageName: json['package_name'] as String? ??
          json['network_packages']?['name'] as String?,
      quantity: (json['quantity'] as num?)?.toInt() ??
          (json['units_purchased'] as num?)?.toInt() ??
          1,
      unitPrice: (json['unit_price'] as num?)?.toInt() ??
          (json['amount_paid'] as num?)?.toInt() ??
          0,
      totalPrice: (json['total_price'] as num?)?.toInt() ??
          (json['amount_paid'] as num?)?.toInt() ??
          0,
      currency: json['currency'] as String? ?? 'YER',
      status: json['status'] as String? ?? 'completed',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      grossAmount: gross,
      commissionRateSnapshot: commissionRate,
      commissionAmount: commission,
      ownerNetAmount: net,
    );
  }
}

class CardRevealResult {
  final String purchaseId;
  final String status;
  final String keyVersion;
  final String ciphertextB64;
  final String nonce;
  final String? authTagB64;
  final DateTime? revealedAt;
  final DateTime? disputeDeadline;

  const CardRevealResult({
    required this.purchaseId,
    required this.status,
    required this.keyVersion,
    required this.ciphertextB64,
    required this.nonce,
    this.authTagB64,
    this.revealedAt,
    this.disputeDeadline,
  });

  factory CardRevealResult.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return CardRevealResult(
      purchaseId: json['purchase_id'] as String? ?? '',
      status: json['status'] as String? ?? 'revealed',
      keyVersion: json['key_version'] as String? ?? 'v1',
      ciphertextB64: json['ciphertext_b64'] as String? ?? '',
      nonce: json['nonce'] as String? ?? '',
      authTagB64: json['auth_tag_b64'] as String?,
      revealedAt: json['revealed_at'] != null
          ? DateTime.parse(json['revealed_at'] as String)
          : now,
      disputeDeadline: json['dispute_deadline'] != null
          ? DateTime.parse(json['dispute_deadline'] as String)
          : now.add(const Duration(minutes: 30)),
    );
  }
}

class RevealedCardInfo {
  final String purchaseId;
  final String plaintext;
  final DateTime? disputeDeadline;

  const RevealedCardInfo({
    required this.purchaseId,
    required this.plaintext,
    this.disputeDeadline,
  });
}

class FulfillmentRecord {
  final String id;
  final String purchaseOrderId;
  final String packageId;
  final String networkId;
  final String? packageName;
  final String? networkName;
  final String status;
  final DateTime? disputeWindowEndsAt;
  final DateTime? createdAt;

  const FulfillmentRecord({
    required this.id,
    required this.purchaseOrderId,
    required this.packageId,
    required this.networkId,
    this.packageName,
    this.networkName,
    required this.status,
    this.disputeWindowEndsAt,
    this.createdAt,
  });

  factory FulfillmentRecord.fromJson(Map<String, dynamic> json) {
    return FulfillmentRecord(
      id: json['fulfillment_id'] as String? ?? json['id'] as String? ?? '',
      purchaseOrderId: json['purchase_order_id'] as String? ?? '',
      packageId: json['package_id'] as String? ?? '',
      networkId: json['network_id'] as String? ?? '',
      packageName: json['package_name'] as String?,
      networkName: json['network_name'] as String?,
      status: json['status'] as String? ?? 'pending_secret',
      disputeWindowEndsAt: json['dispute_window_ends_at'] != null
          ? DateTime.parse(json['dispute_window_ends_at'] as String)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }
}
