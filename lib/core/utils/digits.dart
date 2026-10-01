// lib/core/utils/digits.dart

const _arabicIndicDigits = '٠١٢٣٤٥٦٧٨٩';
const _persianDigits = '۰۱۲۳۴۵۶۷۸۹';

/// Converts Arabic-Indic (٠-٩) and Persian (۰-۹) digits to ASCII 0-9 so that
/// numbers typed on an Arabic keyboard parse with [int.tryParse]. All other
/// characters are kept as-is.
String normalizeDigits(String input) {
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    final character = String.fromCharCode(rune);
    final arabicIndex = _arabicIndicDigits.indexOf(character);
    final persianIndex = _persianDigits.indexOf(character);
    if (arabicIndex >= 0) {
      buffer.write(arabicIndex);
    } else if (persianIndex >= 0) {
      buffer.write(persianIndex);
    } else {
      buffer.write(character);
    }
  }
  return buffer.toString();
}
