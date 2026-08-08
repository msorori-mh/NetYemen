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
      _deposits[index]['status'] = action == 'approve' ? 'approved' : 'rejected';
      _deposits[index]['rejection_reason'] = notes;
    }
  }
}
