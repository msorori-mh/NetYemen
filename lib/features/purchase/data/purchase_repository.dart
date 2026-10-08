// lib/features/purchase/data/purchase_repository.dart

import '../domain/entities.dart';

abstract class PurchaseRepository {
  /// Buys one card of [packageId].
  ///
  /// [expectedPrice] is the whole-YER price the customer saw and confirmed.
  /// The server refuses the purchase with `PRICE_CHANGED` when the current
  /// price differs, so a customer is never charged an amount they did not see.
  Future<Map<String, dynamic>> purchasePackage({
    required String packageId,
    required String idempotencyKey,
    required int expectedPrice,
  });

  /// One purchase of the signed-in customer, or null when it does not exist
  /// or is not theirs.
  Future<PurchaseOrder?> getMyPurchaseOrder(String purchaseId);
  Future<List<PurchaseOrder>> getMyPurchaseOrders();
  Future<List<FulfillmentRecord>> getMyFulfillmentRecords();
  Future<CardRevealResult> revealPurchaseCardSecret(String purchaseId);
  Future<void> submitInvalidCardDispute(String purchaseId, String reason);
}
