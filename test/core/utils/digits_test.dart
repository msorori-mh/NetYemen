import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/core/utils/digit_input_formatter.dart';
import 'package:netyemen/core/utils/digits.dart';

void main() {
  group('normalizeDigits', () {
    test('converts Arabic-Indic and Persian digits to ASCII', () {
      expect(normalizeDigits('٠١٢٣٤٥٦٧٨٩'), '0123456789');
      expect(normalizeDigits('۰۱۲۳۴۵۶۷۸۹'), '0123456789');
      expect(normalizeDigits('REF-٤٢'), 'REF-42');
    });
  });

  group('parseWholeAmount', () {
    test('parses ASCII, Arabic-Indic and Persian digits', () {
      expect(parseWholeAmount('5000'), 5000);
      expect(parseWholeAmount('٥٠٠٠'), 5000);
      expect(parseWholeAmount('۵۰۰۰'), 5000);
      expect(parseWholeAmount(' 5,000 '), 5000);
    });

    test('rejects anything that is not a whole amount', () {
      expect(parseWholeAmount(''), isNull);
      expect(parseWholeAmount('abc'), isNull);
      expect(parseWholeAmount('-5'), isNull);
      expect(parseWholeAmount('12.5'), isNull);
    });
  });

  group('LocalizedDigitsInputFormatter', () {
    TextEditingValue format(String text, {int? maxLength}) {
      final formatter = LocalizedDigitsInputFormatter(maxLength: maxLength);
      return formatter.formatEditUpdate(
        TextEditingValue.empty,
        TextEditingValue(text: text),
      );
    }

    test('keeps every supported digit set', () {
      expect(format('123').text, '123');
      expect(format('١٢٣').text, '١٢٣');
      expect(format('۱۲۳').text, '۱۲۳');
    });

    test('drops non-digits and honours the length limit', () {
      expect(format('1a2-3 ').text, '123');
      expect(format('1234567', maxLength: 6).text, '123456');
    });
  });
}
