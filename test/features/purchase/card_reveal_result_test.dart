import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/features/purchase/domain/entities.dart';

void main() {
  group('CardRevealResult', () {
    test('parses only server-decrypted plaintext for customer display', () {
      final result = CardRevealResult.fromJson({
        'purchase_id': 'purchase-1',
        'status': 'revealed',
        'plaintext': 'CARD-123456',
        'revealed_at': '2026-09-19T02:00:00Z',
        'dispute_deadline': '2026-09-19T02:30:00Z',
      });

      expect(result.plaintext, 'CARD-123456');
      expect(result.purchaseId, 'purchase-1');
      expect(result.disputeDeadline, DateTime.utc(2026, 9, 19, 2, 30));
    });

    test('never treats ciphertext as a displayable card secret', () {
      final result = CardRevealResult.fromJson({
        'purchase_id': 'purchase-1',
        'ciphertext_b64': 'Q0lQSEVSVEVYVA==',
        'nonce': 'not-displayable',
        'auth_tag_b64': 'not-displayable',
      });

      expect(result.plaintext, isEmpty);
      expect(result.disputeDeadline, isNull);
    });
  });
}
