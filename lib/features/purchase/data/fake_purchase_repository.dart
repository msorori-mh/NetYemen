// lib/features/purchase/data/fake_purchase_repository.dart

import '../../../core/utils/uuid_generator.dart';
import 'purchase_repository.dart';
import '../domain/entities.dart';

class FakePurchaseRepository implements PurchaseRepository {
  final List<PurchaseOrder> _orders = [];
  final List<FulfillmentRecord> _fulfillments = [];
  final Map<String, ({String packageId, Map<String, dynamic> result})>
      _idempotentResults = {};

  List<PurchaseOrder> get orders => List.unmodifiable(_orders);

  @override
  Future<Map<String, dynamic>> purchasePackage({
    required String packageId,
    required String idempotencyKey,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));

    final existing = _idempotentResults[idempotencyKey];
    if (existing != null) {
      if (existing.packageId != packageId) {
        throw StateError('IDEMPOTENCY_CONFLICT');
      }
      return {...existing.result, 'replayed': true};
    }

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

    final result = <String, dynamic>{
      'purchase_id': purchaseId,
      'fulfillment_id': fulfillmentId,
      'status': 'completed',
      'amount_paid': 1000,
      'new_balance': 4000,
      'fulfillment_status': 'pending_secret',
    };
    _idempotentResults[idempotencyKey] = (
      packageId: packageId,
      result: result,
    );
    return result;
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
      plaintext: 'DEMO-CARD-123456',
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
