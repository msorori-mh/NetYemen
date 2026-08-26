// lib/features/purchase/data/fake_purchase_repository.dart

import '../../../core/utils/uuid_generator.dart';
import 'purchase_repository.dart';
import '../domain/entities.dart';

class FakePurchaseRepository implements PurchaseRepository {
  final List<PurchaseOrder> _orders = [];
  final List<FulfillmentRecord> _fulfillments = [];

  @override
  Future<Map<String, dynamic>> purchasePackage({
    required String packageId,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final purchaseId = UuidGenerator.generateV4();
    final fulfillmentId = UuidGenerator.generateV4();
    final now = DateTime.now();

    const gross = 1000;
    const rate = 0.03;
    const commission = 30;
    const net = 970;

    _orders.add(
      PurchaseOrder(
        id: purchaseId,
        packageId: packageId,
        networkId: 'fake-network',
        packageName: 'باقة تجريبية',
        quantity: 1,
        unitPrice: gross,
        totalPrice: gross,
        currency: 'YER',
        status: 'completed',
        createdAt: now,
        grossAmount: gross,
        commissionRateSnapshot: rate,
        commissionAmount: commission,
        ownerNetAmount: net,
      ),
    );

    _fulfillments.add(
      FulfillmentRecord(
        id: fulfillmentId,
        purchaseOrderId: purchaseId,
        packageId: packageId,
        networkId: 'fake-network',
        packageName: 'باقة تجريبية',
        status: 'pending_secret',
        disputeWindowEndsAt: now.add(const Duration(hours: 24)),
        createdAt: now,
      ),
    );

    return {
      'purchase_id': purchaseId,
      'fulfillment_id': fulfillmentId,
      'status': 'completed',
      'amount_paid': 1000,
      'new_balance': 4000,
      'fulfillment_status': 'pending_secret',
    };
  }

  @override
  Future<List<PurchaseOrder>> getMyPurchaseOrders() async {
    await Future.delayed(const Duration(milliseconds: 200));
    return List.unmodifiable(_orders);
  }

  @override
  Future<List<FulfillmentRecord>> getMyFulfillmentRecords() async {
    await Future.delayed(const Duration(milliseconds: 200));
    return List.unmodifiable(_fulfillments);
  }

  @override
  Future<CardRevealResult> revealPurchaseCardSecret(String purchaseId) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final deadline = DateTime.now().add(const Duration(minutes: 30));
    return CardRevealResult(
      purchaseId: purchaseId,
      status: 'revealed',
      keyVersion: 'v1-demo',
      ciphertextB64: 'ZGVtby1jaXBoZXJ0ZXh0',
      nonce: 'demo-nonce-123',
      authTagB64: 'demo-auth-tag',
      revealedAt: DateTime.now(),
      disputeDeadline: deadline,
    );
  }

  @override
  Future<void> submitInvalidCardDispute(
    String purchaseId,
    String reason,
  ) async {
    await Future.delayed(const Duration(milliseconds: 300));
    if (reason.trim().isEmpty) {
      throw ArgumentError('REASON_REQUIRED');
    }
  }
}
