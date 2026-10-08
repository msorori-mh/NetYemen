import 'package:flutter_test/flutter_test.dart';
import 'package:owner/utils/card_batch_validator.dart';

void main() {
  group('validateCardBatch', () {
    test('trims lines and drops empty ones', () {
      final result = validateCardBatch('  1111  \n\n2222\n   \n3333');

      expect(result.validPins, ['1111', '2222', '3333']);
      expect(result.emptyLines, 2);
      expect(result.duplicateCount, 0);
      expect(result.invalidCount, 0);
      expect(result.canUpload, isTrue);
    });

    test('handles Windows and old Mac line endings', () {
      final result = validateCardBatch('1111\r\n2222\r3333\n');

      expect(result.validPins, ['1111', '2222', '3333']);
      expect(result.invalidCount, 0);
    });

    test('de-duplicates within the batch and reports line numbers only', () {
      final result = validateCardBatch('1111\n2222\n1111\n\n 2222 \n3333');

      expect(result.validPins, ['1111', '2222', '3333']);
      expect(result.duplicateCount, 2);
      expect(result.duplicateLines, [3, 5]);
      // Duplicates are dropped silently; the rest can still be uploaded.
      expect(result.canUpload, isTrue);
    });

    test('accepts a 64-character PIN and rejects a 65-character one', () {
      final ok = 'a' * maxCardPinLength;
      final tooLong = 'a' * (maxCardPinLength + 1);
      final result = validateCardBatch('$ok\n$tooLong');

      expect(result.validPins, [ok]);
      expect(result.invalidLines, [2]);
      expect(result.canUpload, isFalse);
    });

    test('rejects PINs containing whitespace or control characters', () {
      final lines = [
        '1234 5678', // inner space
        '1234\t5678', // tab
        '1234\u00005678', // NUL
        '1234\u200B5678', // zero-width space
        '1234\u00A05678', // non-breaking space
        '12345678',
      ];
      final result = validateCardBatch(lines.join('\n'));

      expect(result.validPins, ['12345678']);
      expect(result.invalidLines, [1, 2, 3, 4, 5]);
      expect(result.invalidCount, 5);
      expect(result.canUpload, isFalse);
    });

    test('an empty or blank text has nothing to upload', () {
      expect(validateCardBatch('').canUpload, isFalse);
      expect(validateCardBatch(' \n\n ').canUpload, isFalse);
      expect(validateCardBatch(' \n\n ').validCount, 0);
    });

    test('caps the batch at 5000 valid cards', () {
      final atLimit = List.generate(maxCardBatchSize, (i) => 'pin$i');
      final overLimit = [...atLimit, 'one-more'];

      final okResult = validateCardBatch(atLimit.join('\n'));
      expect(okResult.validCount, maxCardBatchSize);
      expect(okResult.exceedsLimit, isFalse);
      expect(okResult.canUpload, isTrue);

      final overResult = validateCardBatch(overLimit.join('\n'));
      expect(overResult.exceedsLimit, isTrue);
      expect(overResult.canUpload, isFalse);
    });

    test('duplicates do not count towards the limit', () {
      final lines = List.generate(maxCardBatchSize, (i) => 'pin$i');
      final result = validateCardBatch([...lines, 'pin0', 'pin1'].join('\n'));

      expect(result.validCount, maxCardBatchSize);
      expect(result.duplicateCount, 2);
      expect(result.canUpload, isTrue);
    });
  });

  group('isValidCardPin', () {
    test('rejects the empty string', () {
      expect(isValidCardPin(''), isFalse);
    });

    test('accepts digits, letters and dashes', () {
      expect(isValidCardPin('1234-ABCD-efgh'), isTrue);
    });
  });

  group('formatLineNumbers', () {
    test('lists every line when short', () {
      expect(formatLineNumbers([3, 7, 9]), '3، 7، 9');
    });

    test('truncates long lists with a remaining count', () {
      final lines = List.generate(15, (i) => i + 1);

      expect(formatLineNumbers(lines, max: 3), '1، 2، 3 … (+12)');
    });
  });

  group('cardExpiryIsoUtc', () {
    test('is the end of the chosen local day expressed in UTC', () {
      final iso = cardExpiryIsoUtc(DateTime(2026, 3, 5));

      expect(iso, endsWith('Z'));
      final parsed = DateTime.parse(iso);
      expect(parsed.isUtc, isTrue);
      expect(parsed.toLocal(), DateTime(2026, 3, 5, 23, 59, 59));
    });

    test('ignores the time of day of the picked value', () {
      expect(
        cardExpiryIsoUtc(DateTime(2026, 3, 5, 9, 30)),
        cardExpiryIsoUtc(DateTime(2026, 3, 5)),
      );
    });
  });

  group('CardBatchKeyTracker', () {
    String signature({String packageId = 'pkg', List<String>? pins}) {
      return cardBatchSignature(
        networkId: 'net',
        packageId: packageId,
        expiresAt: null,
        pins: pins ?? const ['1111', '2222'],
      );
    }

    test('reuses the key when the same batch is retried', () {
      var generated = 0;
      final tracker = CardBatchKeyTracker(() => 'key-${++generated}');

      final first = tracker.keyFor(signature());
      final retry = tracker.keyFor(signature());

      expect(first, 'key-1');
      expect(retry, first);
      expect(generated, 1);
    });

    test('issues a new key when the content changes', () {
      var generated = 0;
      final tracker = CardBatchKeyTracker(() => 'key-${++generated}');

      final first = tracker.keyFor(signature());
      final edited = tracker.keyFor(signature(pins: const ['1111', '3333']));
      final otherPackage = tracker.keyFor(
        signature(packageId: 'other', pins: const ['1111', '3333']),
      );

      expect(edited, isNot(first));
      expect(otherPackage, isNot(edited));
      expect(generated, 3);
    });

    test('issues a new key after a confirmed success', () {
      var generated = 0;
      final tracker = CardBatchKeyTracker(() => 'key-${++generated}');

      final first = tracker.keyFor(signature());
      tracker.confirmSuccess();
      final next = tracker.keyFor(signature());

      expect(next, isNot(first));
    });

    test('the signature changes with the expiry date', () {
      final withoutExpiry = cardBatchSignature(
        networkId: 'net',
        packageId: 'pkg',
        expiresAt: null,
        pins: const ['1111'],
      );
      final withExpiry = cardBatchSignature(
        networkId: 'net',
        packageId: 'pkg',
        expiresAt: '2026-03-05T20:59:59.000Z',
        pins: const ['1111'],
      );

      expect(withExpiry, isNot(withoutExpiry));
    });
  });

  group('CardBatchUploadResult', () {
    test('parses the server result', () {
      final result = CardBatchUploadResult.fromJson({
        'batch_id': 'b-1',
        'ingested_count': 7,
        'duplicates_skipped': 2,
        'replayed': true,
      });

      expect(result.batchId, 'b-1');
      expect(result.ingestedCount, 7);
      expect(result.duplicatesSkipped, 2);
      expect(result.replayed, isTrue);
    });

    test('defaults missing fields instead of throwing', () {
      final result = CardBatchUploadResult.fromJson({
        'batch_id': 'b-2',
        'ingested_count': 3,
      });

      expect(result.duplicatesSkipped, 0);
      expect(result.replayed, isFalse);
    });
  });
}
