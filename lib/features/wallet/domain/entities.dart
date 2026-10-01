// lib/features/wallet/domain/entities.dart

class WalletSummary {
  final String userId;
  final int balance;
  final String currency;
  final String accountStatus;

  const WalletSummary({
    required this.userId,
    required this.balance,
    required this.currency,
    required this.accountStatus,
  });

  factory WalletSummary.fromJson(Map<String, dynamic> json) {
    return WalletSummary(
      userId: json['user_id'] as String? ?? '',
      balance: (json['cached_balance'] as num?)?.toInt() ?? 0,
      currency: json['currency'] as String? ?? 'YER',
      accountStatus: json['account_status'] as String? ?? 'active',
    );
  }
}

class DepositRequest {
  final String id;
  final int amount;
  final String currency;
  final String status;
  final String? channelId;
  final String? proofReference;
  final String? reviewerNotes;
  final DateTime? createdAt;

  const DepositRequest({
    required this.id,
    required this.amount,
    required this.currency,
    required this.status,
    this.channelId,
    this.proofReference,
    this.reviewerNotes,
    this.createdAt,
  });

  factory DepositRequest.fromJson(Map<String, dynamic> json) {
    return DepositRequest(
      id: json['id'] as String? ?? '',
      amount: (json['amount'] as num?)?.toInt() ?? 0,
      currency: json['currency'] as String? ?? 'YER',
      status: json['status'] as String? ?? 'submitted',
      channelId: json['bank_directory_id'] as String?,
      proofReference: json['proof_storage_path'] as String?,
      reviewerNotes: json['rejection_reason'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }
}

class DepositChannel {
  final String id;
  final String displayName;
  final String channelType;
  final String? accountReference;
  final String? instructions;
  final bool isActive;

  const DepositChannel({
    required this.id,
    required this.displayName,
    required this.channelType,
    this.accountReference,
    this.instructions,
    required this.isActive,
  });

  factory DepositChannel.fromJson(Map<String, dynamic> json) {
    return DepositChannel(
      id: json['id'] as String? ?? '',
      displayName: json['display_name'] as String? ??
          json['provider_name'] as String? ??
          '',
      channelType: json['provider_type'] as String? ?? 'bank_account',
      accountReference: json['account_identifier'] as String? ??
          json['account_number'] as String? ??
          json['iban'] as String?,
      instructions:
          json['instructions'] as String? ?? json['account_label'] as String?,
      isActive: json['is_active'] as bool? ?? false,
    );
  }
}
