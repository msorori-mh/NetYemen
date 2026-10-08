// lib/features/purchase/data/fake_purchase_repository.dart

import '../../../core/utils/uuid_generator.dart';
import 'purchase_repository.dart';
import '../domain/entities.dart';

class FakePurchaseRepository implements PurchaseRepository {
  final List<PurchaseOrder> _orders = [];
  final List<FulfillmentRecord> _fulfillments = [];
  final Map<String, _FakePurchaseReplay> _idempotentResults = {};

  /// Test hook mirroring the server: when set, a purchase whose
  /// `expectedPrice` differs is refused with `PRICE_CHANGED`.
  int? currentPriceOverride;

  List<PurchaseOrder> get orders => List.unmodifiable(_orders);

  @override
  Future<Map<String, dynamic>> purchasePackage({
    required String packageId,
    required String idempotencyKey,
    required int expectedPrice,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));

    final existing = _idempotentResults[idempotencyKey];
    if (existing != null) {
      if (existing.packageId != packageId ||
          existing.expectedPrice != expectedPrice) {
        throw StateError('IDEMPOTENCY_CONFLICT');
      }
      return {...existing.result, 'replayed': true};
    }

    final currentPrice = currentPriceOverride;
    if (currentPrice != null && currentPrice != expectedPrice) {
      throw StateError('PRICE_CHANGED: package price changed');
    }

    final purchaseId = UuidGenerator.generateV4();
    final fulfillmentId = UuidGenerator.generateV4();
    final now = DateTime.now();

    // Whole YER, exactly the price the customer confirmed.
    final gross = expectedPrice;
    const rate = 0.03;
    final commission = (gross * rate).floor();
    final net = gross - commission;

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
      'amount_paid': gross,
      'currency': 'YER',
      'fulfillment_status': 'pending_secret',
    };
    _idempotentResults[idempotencyKey] = _FakePurchaseReplay(
      packageId: packageId,
      expectedPrice: expectedPrice,
      result: result,
    );
    return result;
  }

  @override
  Future<PurchaseOrder?> getMyPurchaseOrder(String purchaseId) async {
    await Future.delayed(const Duration(milliseconds: 200));
    for (final order in _orders) {
      if (order.id == purchaseId) return order;
    }
    return null;
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

class _FakePurchaseReplay {
  final String packageId;
  final int expectedPrice;
  final Map<String, dynamic> result;

  const _FakePurchaseReplay({
    required this.packageId,
    required this.expectedPrice,
    required this.result,
  });
}
