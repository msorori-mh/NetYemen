/// Single formatter for every customer-visible amount.
///
/// Amounts are whole Yemeni rials (integers). There is no sub-unit, so
/// nothing here divides or multiplies: the integer the server stores is the
/// integer the customer sees, grouped in thousands for readability.
String formatYer(int amount, {String currency = 'YER'}) {
  final grouped = groupThousands(amount);
  final label = currency.trim();
  return label.isEmpty ? grouped : '$grouped $label';
}

/// Groups [amount] in thousands with an ASCII comma, e.g. `12500` -> `12,500`.
String groupThousands(int amount) {
  final digits = amount.abs().toString();
  final buffer = StringBuffer();
  if (amount < 0) buffer.write('-');
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) buffer.write(',');
    buffer.write(digits[index]);
  }
  return buffer.toString();
}
