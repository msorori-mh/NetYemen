import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/features/finance/domain/finance_operation_policy.dart';

void main() {
  group('FinanceOperationPolicy settlement periods', () {
    test('accepts an ordered period', () {
      expect(
        FinanceOperationPolicy.isValidSettlementPeriod(
          DateTime(2026, 8, 1),
          DateTime(2026, 8, 19),
        ),
        isTrue,
      );
    });

    test('accepts a single-day period', () {
      final day = DateTime(2026, 8, 19);
      expect(
        FinanceOperationPolicy.isValidSettlementPeriod(day, day),
        isTrue,
      );
    });

    test('rejects a reversed period', () {
      expect(
        FinanceOperationPolicy.isValidSettlementPeriod(
          DateTime(2026, 8, 20),
          DateTime(2026, 8, 19),
        ),
        isFalse,
      );
    });
  });

  group('FinanceOperationPolicy payment notes', () {
    test('normalizes whitespace-only notes to null', () {
      expect(FinanceOperationPolicy.normalizePaymentNotes('   '), isNull);
    });

    test('trims valid notes', () {
      expect(
        FinanceOperationPolicy.normalizePaymentNotes('  transfer verified  '),
        'transfer verified',
      );
    });

    test('rejects notes beyond the server-safe limit', () {
      expect(
        () => FinanceOperationPolicy.normalizePaymentNotes(
          'x' * (FinanceOperationPolicy.maximumPaymentNotesLength + 1),
        ),
        throwsFormatException,
      );
    });
  });
}
