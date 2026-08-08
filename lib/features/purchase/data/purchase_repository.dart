// lib/features/purchase/data/purchase_repository.dart

import '../domain/entities.dart';

abstract class PurchaseRepository {
  Future<Map<String, dynamic>> purchasePackage({
    required String packageId,
  });
  Future<List<PurchaseOrder>> getMyPurchaseOrders();
  Future<List<FulfillmentRecord>> getMyFulfillmentRecords();
  Future<CardRevealResult> revealPurchaseCardSecret(String purchaseId);
  Future<void> submitInvalidCardDispute(String purchaseId, String reason);
}
