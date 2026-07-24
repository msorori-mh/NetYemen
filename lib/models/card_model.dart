// lib/models/card_model.dart
class CardModel {
  final String id;
  final String networkId;
  final String cardNumber;
  final int denomination;
  final String status;
  final String? soldTo;
  final DateTime? soldAt;
  final DateTime? createdAt;

  CardModel({
    required this.id,
    required this.networkId,
    required this.cardNumber,
    required this.denomination,
    this.status = 'available',
    this.soldTo,
    this.soldAt,
    this.createdAt,
  });

  factory CardModel.fromJson(Map<String, dynamic> json) {
    return CardModel(
      id: json['id'] ?? '',
      networkId: json['network_id'] ?? '',
      cardNumber: json['card_number'] ?? '',
      denomination: json['denomination'] ?? 0,
      status: json['status'] ?? 'available',
      soldTo: json['sold_to'],
      soldAt: json['sold_at'] != null 
          ? DateTime.parse(json['sold_at']) 
          : null,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at']) 
          : null,
    );
  }
}

class Purchase {
  final String id;
  final String userId;
  final String? cardId;
  final String? networkId;
  final String cardNumber;
  final int denomination;
  final int amount;
  final DateTime? createdAt;

  Purchase({
    required this.id,
    required this.userId,
    this.cardId,
    this.networkId,
    required this.cardNumber,
    required this.denomination,
    required this.amount,
    this.createdAt,
  });

  factory Purchase.fromJson(Map<String, dynamic> json) {
    return Purchase(
      id: json['id'] ?? '',
      userId: json['user_id'] ?? '',
      cardId: json['card_id'],
      networkId: json['network_id'],
      cardNumber: json['card_number'] ?? '',
      denomination: json['denomination'] ?? 0,
      amount: json['amount'] ?? 0,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at']) 
          : null,
    );
  }

  String get maskedCardNumber {
    if (cardNumber.length <= 4) return cardNumber;
    return '${cardNumber.substring(0, 2)}****${cardNumber.substring(cardNumber.length - 2)}';
  }

  String get formattedDate {
    if (createdAt == null) return '';
    return '${createdAt!.day}/${createdAt!.month}/${createdAt!.year}';
  }
}
