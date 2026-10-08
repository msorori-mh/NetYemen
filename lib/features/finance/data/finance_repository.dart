// lib/features/finance/data/finance_repository.dart

abstract class FinanceRepository {
  Future<List<Map<String, dynamic>>> getDepositQueue(String? status);
  Future<void> reviewDeposit(String id, String action, {String? notes});
  Future<List<Map<String, dynamic>>> getActivePaymentDestinations();
  Future<List<Map<String, dynamic>>> getPaymentDestinations();
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
  Future<Map<String, dynamic>> setPaymentDestinationActive(
    String id,
    bool active,
  );
  Future<Map<String, dynamic>> reorderPaymentDestinations(
    List<String> orderedIds,
  );
  Future<Map<String, dynamic>> createSettlementBatch({
    required DateTime periodStart,
    required DateTime periodEnd,
    String? networkId,
  });
  Future<Map<String, dynamic>> approveSettlementBatch(String batchId);

  /// Marks an approved batch as paid.
  ///
  /// [paymentReference] is the reference of the transfer that paid the owner.
  /// The server requires it (`PAYMENT_REFERENCE_REQUIRED` when blank).
  Future<Map<String, dynamic>> markSettlementPaid(
    String batchId, {
    required String paymentReference,
  });

  /// Cancels a batch that is still a draft or waiting for review and releases
  /// its items. The server requires [reason] (`REASON_REQUIRED` when blank).
  Future<Map<String, dynamic>> cancelSettlementBatch(
    String batchId, {
    required String reason,
  });

  Future<List<Map<String, dynamic>>> getFinanceSettlementBatches(
    String? status,
  );
  Future<List<Map<String, dynamic>>> getOwnerSettlements(String? networkId);
}
