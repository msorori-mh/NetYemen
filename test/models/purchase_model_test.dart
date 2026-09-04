import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/models/purchase_model.dart';

void main() {
  group('PurchaseResult.fromJson', () {
    test('parses the direct purchase_card RPC return row', () {
      final json = {
        'purchase_id': 'purchase-1',
        'card_number': '1234567890123456',
        'price_paid': 1000,
        'purchased_at': '2026-01-01T12:00:00.000Z',
      };

      final result = PurchaseResult.fromJson(json);

      expect(result.purchaseId, 'purchase-1');
      expect(result.cardNumber, '1234567890123456');
      expect(result.pricePaid, 1000);
      expect(result.purchasedAt, DateTime.parse('2026-01-01T12:00:00.000Z'));
    });
  });

  group('Purchase.fromJson', () {
    test('parses a purchases row with the joined network name, no card_number',
        () {
      final json = {
        'id': 'purchase-1',
        'user_id': 'user-1',
        'card_id': 'card-1',
        'network_id': 'net-1',
        'network_price_id': 'price-1',
        'price_paid': 1000,
        'networks': {'name': 'Yemen Net Fast'},
        'created_at': '2026-03-05T00:00:00.000Z',
      };

      final purchase = Purchase.fromJson(json);

      expect(purchase.id, 'purchase-1');
      expect(purchase.cardId, 'card-1');
      expect(purchase.networkId, 'net-1');
      expect(purchase.networkName, 'Yemen Net Fast');
      expect(purchase.pricePaid, 1000);
      expect(purchase.formattedDate, '5/3/2026');
    });

    test('handles a missing joined network gracefully', () {
      final json = {
        'id': 'purchase-2',
        'user_id': 'user-1',
        'card_id': 'card-2',
        'network_id': 'net-2',
        'network_price_id': 'price-2',
        'price_paid': 500,
      };

      final purchase = Purchase.fromJson(json);

      expect(purchase.networkName, isNull);
      expect(purchase.formattedDate, '');
    });
  });
}
