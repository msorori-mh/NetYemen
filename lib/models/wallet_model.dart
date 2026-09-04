// lib/models/wallet_model.dart

class WalletLedgerEntry {
  final String id;
  final String entryType; // CREDIT | DEBIT | REVERSAL
  final int amount;
  final int balanceAfter;
  final String referenceType; // DEPOSIT | PURCHASE | REFUND | SETTLEMENT | ADJUSTMENT
  final String reasonCode;
  final DateTime createdAt;

  WalletLedgerEntry({
    required this.id,
    required this.entryType,
    required this.amount,
    required this.balanceAfter,
    required this.referenceType,
    required this.reasonCode,
    required this.createdAt,
  });

  factory WalletLedgerEntry.fromJson(Map<String, dynamic> json) {
    return WalletLedgerEntry(
      id: json['id'] ?? '',
      entryType: json['entry_type'] ?? '',
      amount: json['amount'] ?? 0,
      balanceAfter: json['balance_after'] ?? 0,
      referenceType: json['reference_type'] ?? '',
      reasonCode: json['reason_code'] ?? '',
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  bool get isCredit => entryType == 'CREDIT' || entryType == 'REVERSAL';

  String get referenceLabel {
    switch (referenceType) {
      case 'DEPOSIT':
        return 'شحن رصيد';
      case 'PURCHASE':
        return 'شراء كرت';
      case 'REFUND':
        return 'استرجاع';
      case 'SETTLEMENT':
        return 'تسوية';
      default:
        return 'تعديل';
    }
  }
}

class WalletDepositRequest {
  final String id;
  final int amount;
  final String depositChannel;
  final String status; // pending | under_review | approved | rejected
  final String? rejectionReason;
  final DateTime createdAt;

  WalletDepositRequest({
    required this.id,
    required this.amount,
    required this.depositChannel,
    required this.status,
    this.rejectionReason,
    required this.createdAt,
  });

  factory WalletDepositRequest.fromJson(Map<String, dynamic> json) {
    return WalletDepositRequest(
      id: json['id'] ?? '',
      amount: json['amount'] ?? 0,
      depositChannel: json['deposit_channel'] ?? '',
      status: json['status'] ?? 'pending',
      rejectionReason: json['rejection_reason'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  String get statusLabel {
    switch (status) {
      case 'pending':
        return 'قيد الانتظار';
      case 'under_review':
        return 'قيد المراجعة';
      case 'approved':
        return 'تمت الموافقة';
      case 'rejected':
        return 'مرفوض';
      default:
        return status;
    }
  }
}

class BankAccount {
  final String id;
  final String providerName;
  final String accountHolderName;
  final String accountNumber;
  final String? branch;
  final String? notes;

  BankAccount({
    required this.id,
    required this.providerName,
    required this.accountHolderName,
    required this.accountNumber,
    this.branch,
    this.notes,
  });

  factory BankAccount.fromJson(Map<String, dynamic> json) {
    return BankAccount(
      id: json['id'] ?? '',
      providerName: json['provider_name'] ?? '',
      accountHolderName: json['account_holder_name'] ?? '',
      accountNumber: json['account_number'] ?? '',
      branch: json['branch'],
      notes: json['notes'],
    );
  }
}
