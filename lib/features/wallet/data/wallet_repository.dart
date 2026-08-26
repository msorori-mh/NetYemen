// lib/features/wallet/data/wallet_repository.dart

import '../domain/entities.dart';

abstract class WalletRepository {
  Future<WalletSummary> getMyWalletSummary();
  Future<List<DepositRequest>> getMyDepositRequests();
  Future<List<DepositChannel>> getActiveDepositChannels();
  Future<String> createDepositRequest({
    required int amount,
    String? paymentDestinationId,
    String? proofReference,
  });
}
