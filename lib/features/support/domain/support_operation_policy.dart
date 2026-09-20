class SupportOperationPolicy {
  const SupportOperationPolicy._();

  static const int maximumActionTextLength = 1000;

  static bool requiresResolution(String status) {
    return status == 'resolved' || status == 'closed';
  }

  static String? normalizeActionText(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return null;
    if (normalized.length > maximumActionTextLength) {
      throw const FormatException('SUPPORT_TEXT_TOO_LONG');
    }
    return normalized;
  }

  static String? validateResolution(String status, String resolution) {
    if (requiresResolution(status) && resolution.trim().isEmpty) {
      return 'يجب إدخال نص الحل قبل حل الحالة أو إغلاقها.';
    }
    if (resolution.trim().length > maximumActionTextLength) {
      return 'تجاوز نص الحل الحد المسموح.';
    }
    return null;
  }
}
