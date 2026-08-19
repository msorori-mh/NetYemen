// lib/features/finance/data/fake_finance_repository.dart

import 'finance_repository.dart';

class FakeFinanceRepository implements FinanceRepository {
  final List<Map<String, dynamic>> _deposits = [
    {
      'id': 'fake-dep-1',
      'user_id': 'fake-user-1',
      'amount': 5000,
      'currency': 'YER',
      'status': 'submitted',
      'proof_reference': 'REF-001',
      'created_at': DateTime.now().toIso8601String(),
    },
  ];

  @override
  Future<List<Map<String, dynamic>>> getDepositQueue(String? status) async {
    await Future.delayed(const Duration(milliseconds: 200));
    if (status == null) return List.unmodifiable(_deposits);
    return List.unmodifiable(_deposits.where((d) => d['status'] == status));
  }

  @override
  Future<void> reviewDeposit(String id, String action, {String? notes}) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final index = _deposits.indexWhere((d) => d['id'] == id);
    if (index >= 0) {
      _deposits[index]['status'] = action == 'approve'
          ? 'approved'
          : 'rejected';
      _deposits[index]['rejection_reason'] = notes;
    }
  }

  final List<Map<String, dynamic>> _paymentDestinations = [
    {
      'id': 'fake-dest-1',
      'provider_type': 'bank_account',
      'display_name': 'بنك الكريمي (تجريبي)',
      'account_holder_name': 'WASEL NET Demo',
      'account_identifier': 'DEMO-123456',
      'instructions': 'Transfer to demo account',
      'currency': 'YER',
      'sort_order': 0,
      'is_active': true,
    },
  ];

  final List<Map<String, dynamic>> _settlementBatches = [];

  @override
  Future<List<Map<String, dynamic>>> getActivePaymentDestinations() async {
    await Future.delayed(const Duration(milliseconds: 100));
    return List.unmodifiable(
      _paymentDestinations.where((d) => d['is_active'] == true),
    );
  }

  @override
  Future<Map<String, dynamic>> createPaymentDestination({
    required String providerType,
    required String displayName,
    String? accountHolderName,
    String? accountIdentifier,
    String? instructions,
    String currency = 'YER',
    int sortOrder = 0,
  }) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final id = 'fake-dest-${_paymentDestinations.length + 1}';
    final destination = {
      'id': id,
      'provider_type': providerType,
      'display_name': displayName,
      'account_holder_name': accountHolderName,
      'account_identifier': accountIdentifier,
      'instructions': instructions,
      'currency': currency,
      'sort_order': sortOrder,
      'is_active': true,
    };
    _paymentDestinations.add(destination);
    return {'id': id};
  }

  @override
  Future<Map<String, dynamic>> updatePaymentDestination(
    String id, {
    String? providerType,
    String? displayName,
    String? accountHolderName,
    String? accountIdentifier,
    String? instructions,
    String? currency,
    int? sortOrder,
  }) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final index = _paymentDestinations.indexWhere((d) => d['id'] == id);
    if (index < 0) throw StateError('NOT_FOUND');
    final d = _paymentDestinations[index];
    if (providerType != null) d['provider_type'] = providerType;
    if (displayName != null) d['display_name'] = displayName;
    if (accountHolderName != null) d['account_holder_name'] = accountHolderName;
    if (accountIdentifier != null) d['account_identifier'] = accountIdentifier;
    if (instructions != null) d['instructions'] = instructions;
    if (currency != null) d['currency'] = currency;
    if (sortOrder != null) d['sort_order'] = sortOrder;
    return {'id': id, 'updated': true};
  }

  @override
  Future<Map<String, dynamic>> setPaymentDestinationActive(
    String id,
    bool active,
  ) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final index = _paymentDestinations.indexWhere((d) => d['id'] == id);
    if (index < 0) throw StateError('NOT_FOUND');
    _paymentDestinations[index]['is_active'] = active;
    return {'id': id, 'is_active': active};
  }

  @override
  Future<Map<String, dynamic>> reorderPaymentDestinations(
    List<String> orderedIds,
  ) async {
    await Future.delayed(const Duration(milliseconds: 200));
    for (var i = 0; i < orderedIds.length; i++) {
      final d = _paymentDestinations.firstWhere(
        (d) => d['id'] == orderedIds[i],
      );
      d['sort_order'] = i;
    }
    return {'updated': orderedIds.length};
  }

  @override
  Future<Map<String, dynamic>> createSettlementBatch({
    required DateTime periodStart,
    required DateTime periodEnd,
    String? networkId,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final id = 'fake-batch-${_settlementBatches.length + 1}';
    final batch = {
      'id': id,
      'period_start': periodStart.toIso8601String().substring(0, 10),
      'period_end': periodEnd.toIso8601String().substring(0, 10),
      'network_id': networkId ?? 'fake-network',
      'network_name': 'شبكة تجريبية',
      'owner_name': 'مالك تجريبي',
      'gross_sales': 5000,
      'total_commission': 150,
      'total_refunds': 0,
      'total_adjustments': 0,
      'net_settlement': 4850,
      'status': 'draft',
      'notes': null,
      'created_at': DateTime.now().toIso8601String(),
    };
    _settlementBatches.add(batch);
    return {'batches_created': 1, 'total_gross_sales': batch['gross_sales']};
  }

  @override
  Future<Map<String, dynamic>> approveSettlementBatch(String batchId) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final batch = _settlementBatches.firstWhere((b) => b['id'] == batchId);
    batch['status'] = 'approved';
    return {'id': batchId, 'status': 'approved'};
  }

  @override
  Future<Map<String, dynamic>> markSettlementPaid(
    String batchId, {
    String? notes,
  }) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final batch = _settlementBatches.firstWhere((b) => b['id'] == batchId);
    batch['status'] = 'paid';
    batch['notes'] = notes;
    return {'id': batchId, 'status': 'paid'};
  }

  @override
  Future<List<Map<String, dynamic>>> getFinanceSettlementBatches(
    String? status,
  ) async {
    await Future.delayed(const Duration(milliseconds: 200));
    if (status == null) return List.unmodifiable(_settlementBatches);
    return List.unmodifiable(
      _settlementBatches.where((b) => b['status'] == status),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getOwnerSettlements(
    String? networkId,
  ) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return List.unmodifiable(_settlementBatches);
  }
}
