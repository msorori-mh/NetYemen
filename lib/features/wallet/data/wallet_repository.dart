// lib/features/wallet/data/wallet_repository.dart

import '../domain/entities.dart';

abstract class WalletRepository {
  Future<WalletSummary> getMyWalletSummary();
  Future<List<DepositRequest>> getMyDepositRequests();
  Future<List<DepositChannel>> getActiveDepositChannels();
  /// Files a deposit request for review.
  ///
  /// [amount] is whole YER. [referenceNumber] is the transfer reference from
  /// the customer's receipt and is required by the server
  /// (`INVALID_REFERENCE` when blank).
  Future<String> createDepositRequest({
    required int amount,
    required String idempotencyKey,
    required String paymentDestinationId,
    required String referenceNumber,
  });
}
