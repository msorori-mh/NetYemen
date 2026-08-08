// lib/features/finance/data/finance_repository.dart

abstract class FinanceRepository {
  Future<List<Map<String, dynamic>>> getDepositQueue(String? status);
  Future<void> reviewDeposit(String id, String action, {String? notes});
  Future<List<Map<String, dynamic>>> getActivePaymentDestinations();
  Future<Map<String, dynamic>> createPaymentDestination({
    required String providerType,
    required String displayName,
    String? accountHolderName,
    String? accountIdentifier,
    String? instructions,
    String currency,
    int sortOrder,
  });
  Future<Map<String, dynamic>> updatePaymentDestination(
    String id, {
    String? providerType,
    String? displayName,
    String? accountHolderName,
    String? accountIdentifier,
    String? instructions,
    String? currency,
    int? sortOrder,
  });
  Future<Map<String, dynamic>> setPaymentDestinationActive(String id, bool active);
  Future<Map<String, dynamic>> reorderPaymentDestinations(List<String> orderedIds);
  Future<Map<String, dynamic>> createSettlementBatch({
    required DateTime periodStart,
    required DateTime periodEnd,
    String? networkId,
  });
  Future<Map<String, dynamic>> approveSettlementBatch(String batchId);
  Future<Map<String, dynamic>> markSettlementPaid(String batchId, {String? notes});
  Future<List<Map<String, dynamic>>> getFinanceSettlementBatches(String? status);
  Future<List<Map<String, dynamic>>> getOwnerSettlements(String? networkId);
}
