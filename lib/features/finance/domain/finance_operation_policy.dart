class FinanceOperationPolicy {
  const FinanceOperationPolicy._();

  static const int maximumPaymentNotesLength = 500;

  static bool isValidSettlementPeriod(DateTime start, DateTime end) {
    return !start.isAfter(end);
  }

  static String? normalizePaymentNotes(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return null;
    if (normalized.length > maximumPaymentNotesLength) {
      throw const FormatException('PAYMENT_NOTES_TOO_LONG');
    }
    return normalized;
  }
}
