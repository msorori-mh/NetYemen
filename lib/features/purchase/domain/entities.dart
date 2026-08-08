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
  });

  factory PurchaseOrder.fromJson(Map<String, dynamic> json) {
    return PurchaseOrder(
      id: json['id'] as String? ?? '',
      packageId: json['package_id'] as String? ?? '',
      networkId: json['network_id'] as String? ?? '',
      networkName: json['network_name'] as String?,
      packageName: json['package_name'] as String?,
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      unitPrice: (json['unit_price'] as num?)?.toInt() ?? 0,
      totalPrice: (json['total_price'] as num?)?.toInt() ?? 0,
      currency: json['currency'] as String? ?? 'YER',
      status: json['status'] as String? ?? 'completed',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }
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
