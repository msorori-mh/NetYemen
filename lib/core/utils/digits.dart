const String _arabicIndicDigits = '٠١٢٣٤٥٦٧٨٩';
const String _persianDigits = '۰۱۲۳۴۵۶۷۸۹';

/// Replaces Arabic-Indic (٠-٩) and Persian (۰-۹) digits with ASCII digits and
/// leaves every other character untouched.
///
/// Arabic keyboards commonly produce these digits; `int.tryParse` rejects
/// them, so every numeric field must normalise before parsing.
String normalizeDigits(String input) {
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    final character = String.fromCharCode(rune);
    final arabicIndex = _arabicIndicDigits.indexOf(character);
    if (arabicIndex >= 0) {
      buffer.write(arabicIndex);
      continue;
    }
    final persianIndex = _persianDigits.indexOf(character);
    if (persianIndex >= 0) {
      buffer.write(persianIndex);
      continue;
    }
    buffer.write(character);
  }
  return buffer.toString();
}

/// Parses a whole, positive-or-zero amount typed by a customer.
///
/// Accepts ASCII, Arabic-Indic and Persian digits, ignores surrounding
/// whitespace and thousands separators, and returns null for anything else
/// (signs, decimals, letters, empty input). Amounts are whole YER.
int? parseWholeAmount(String input) {
  final cleaned = normalizeDigits(input)
      .replaceAll(RegExp(r'[\s,\u066C\u060C]'), '')
      .trim();
  if (cleaned.isEmpty || !RegExp(r'^\d{1,12}$').hasMatch(cleaned)) return null;
  return int.tryParse(cleaned);
}
