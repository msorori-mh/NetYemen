class AdminNotificationPolicy {
  const AdminNotificationPolicy._();

  static const int maximumTitleLength = 120;
  static const int maximumBodyLength = 500;

  static const Set<String> allowedRoles = {
    'platform_admin',
    'finance_officer',
    'support_agent',
    'system_auditor',
    'network_owner',
    'network_operator',
    'customer',
  };

  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  );

  static String? validate({
    required String title,
    required String body,
    required String audienceType,
    required String audienceValue,
  }) {
    final normalizedTitle = title.trim();
    final normalizedBody = body.trim();
    final normalizedAudience = audienceValue.trim();

    if (normalizedTitle.isEmpty || normalizedBody.isEmpty) {
      return 'العنوان والنص مطلوبان.';
    }
    if (normalizedTitle.length > maximumTitleLength ||
        normalizedBody.length > maximumBodyLength) {
      return 'تجاوز محتوى الإعلان الحد المسموح.';
    }
    if (audienceType == 'all_active_customers') return null;
    if (normalizedAudience.isEmpty) {
      return 'يجب تحديد قيمة الجمهور المستهدف.';
    }
    if ({
      'network_related',
      'network_owner_operator',
      'specific_user',
    }.contains(audienceType)) {
      if (!_uuidPattern.hasMatch(normalizedAudience)) {
        return 'معرّف الجمهور غير صالح.';
      }
    }
    if (audienceType == 'role_based' &&
        !allowedRoles.contains(normalizedAudience)) {
      return 'الدور المحدد غير مدعوم.';
    }
    return null;
  }
}
