import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/core/utils/money_format.dart';

void main() {
  group('formatYer', () {
    test('never scales the amount', () {
      expect(formatYer(0), '0 YER');
      expect(formatYer(5), '5 YER');
      expect(formatYer(100), '100 YER');
      expect(formatYer(1000), '1,000 YER');
    });

    test('groups thousands with an ASCII comma', () {
      expect(formatYer(999), '999 YER');
      expect(formatYer(12500), '12,500 YER');
      expect(formatYer(1234567), '1,234,567 YER');
      expect(formatYer(-2500), '-2,500 YER');
    });

    test('uses the currency label it is given', () {
      expect(formatYer(8000, currency: 'ر.ي'), '8,000 ر.ي');
      expect(formatYer(8000, currency: ''), '8,000');
    });
  });
}
