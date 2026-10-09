// lib/features/finance/data/finance_repository.dart

/// What the customer app needs from the finance side: the payment
/// destinations a deposit can be sent to. Staff finance operations (deposit
/// review, payment destinations, settlements) live in the static admin
/// console (admin/), not in this app.
abstract class FinanceRepository {
  Future<List<Map<String, dynamic>>> getActivePaymentDestinations();
}
