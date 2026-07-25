import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/models/card_model.dart';

void main() {
  group('Purchase.maskedCardNumber', () {
    test('handles short card numbers without masking', () {
      final purchase = Purchase(
        id: 'p-1',
        userId: 'u-1',
        cardNumber: '1234',
        denomination: 1000,
        amount: 1000,
      );

      expect(purchase.maskedCardNumber, '1234');
      expect(purchase.cardNumber, '1234');
    });

    test('masks normal length card numbers correctly', () {
      final purchase = Purchase(
        id: 'p-2',
        userId: 'u-1',
        cardNumber: '1234567890',
        denomination: 1000,
        amount: 1000,
      );

      expect(purchase.maskedCardNumber, '12****90');
    });

    test('does not alter the underlying stored card number', () {
      const originalCardNumber = '9876543210123456';
      final purchase = Purchase(
        id: 'p-3',
        userId: 'u-1',
        cardNumber: originalCardNumber,
        denomination: 2000,
        amount: 2000,
      );

      final masked = purchase.maskedCardNumber;

      expect(masked, '98****56');
      expect(purchase.cardNumber, originalCardNumber);
    });
  });
}
