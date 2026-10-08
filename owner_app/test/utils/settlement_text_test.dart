import 'package:flutter_test/flutter_test.dart';
import 'package:owner/utils/settlement_text.dart';

void main() {
  group('settlementAmount', () {
    test('reads integers, numeric strings and null', () {
      expect(settlementAmount(1500), 1500);
      expect(settlementAmount(-250), -250);
      expect(settlementAmount('300'), 300);
      expect(settlementAmount(null), 0);
      expect(settlementAmount('not a number'), 0);
    });
  });

  group('deductionText', () {
    test('shows a deduction with a single minus sign', () {
      expect(deductionText(500), '-500');
      expect(deductionText(-500), '-500');
      expect(deductionText(0), '0');
      expect(deductionText(null), '0');
    });
  });

  group('negative batch net', () {
    test('a batch where refunds exceed sales means the owner owes', () {
      expect(settlementOwnerOwes(-1200), isTrue);
      expect(settlementOwnerOwes(0), isFalse);
      expect(settlementOwnerOwes(900), isFalse);
      expect(settlementNetLabel(-1200), isNot(settlementNetLabel(900)));
    });
  });

  group('labels', () {
    test('every batch status has an Arabic label', () {
      const statuses = [
        'draft',
        'ready_for_review',
        'approved',
        'paid',
        'cancelled',
        'corrected',
      ];

      for (final status in statuses) {
        expect(settlementStatusLabel(status), isNot(status));
      }
    });

    test('unknown values are shown as they are instead of throwing', () {
      expect(settlementStatusLabel('some_future_status'), 'some_future_status');
      expect(settlementStatusLabel(null), '—');
      expect(settlementLineTypeLabel('refund'), 'مرتجع');
      expect(settlementLineTypeLabel('voided'), 'voided');
      expect(settlementLineTypeLabel(null), '—');
    });
  });
}
