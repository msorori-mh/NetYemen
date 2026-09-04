// lib/models/purchase_model.dart
//
// Card numbers are never stored client-side beyond the moment they are
// revealed. `PurchaseResult` carries the plaintext returned directly by the
// purchase_card RPC at the moment of sale (BR-CARD-005); `Purchase` is the
// historical record (no card_number column exists on the `purchases` table
// at all — see NY-BE-005) and re-reveals it on demand via
// SupabaseService.revealPurchasedCard, never caching the result.

class PurchaseResult {
  final String purchaseId;
  final String cardNumber;
  final int pricePaid;
  final DateTime purchasedAt;

  PurchaseResult({
    required this.purchaseId,
    required this.cardNumber,
    required this.pricePaid,
    required this.purchasedAt,
  });

  factory PurchaseResult.fromJson(Map<String, dynamic> json) {
    return PurchaseResult(
      purchaseId: json['purchase_id'] ?? '',
      cardNumber: json['card_number'] ?? '',
      pricePaid: json['price_paid'] ?? 0,
      purchasedAt: json['purchased_at'] != null
          ? DateTime.parse(json['purchased_at'])
          : DateTime.now(),
    );
  }
}

class Purchase {
  final String id;
  final String userId;
  final String cardId;
  final String networkId;
  final String? networkName;
  final String networkPriceId;
  final int pricePaid;
  final DateTime? createdAt;

  Purchase({
    required this.id,
    required this.userId,
    required this.cardId,
    required this.networkId,
    this.networkName,
    required this.networkPriceId,
    required this.pricePaid,
    this.createdAt,
  });

  factory Purchase.fromJson(Map<String, dynamic> json) {
    return Purchase(
      id: json['id'] ?? '',
      userId: json['user_id'] ?? '',
      cardId: json['card_id'] ?? '',
      networkId: json['network_id'] ?? '',
      networkName: json['networks'] != null
          ? json['networks']['name'] as String?
          : null,
      networkPriceId: json['network_price_id'] ?? '',
      pricePaid: json['price_paid'] ?? 0,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
    );
  }

  String get formattedDate {
    if (createdAt == null) return '';
    return '${createdAt!.day}/${createdAt!.month}/${createdAt!.year}';
  }
}
