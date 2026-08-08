// lib/features/finance/data/finance_repository.dart

abstract class FinanceRepository {
  Future<List<Map<String, dynamic>>> getDepositQueue(String? status);
  Future<void> reviewDeposit(String id, String action, {String? notes});
}
