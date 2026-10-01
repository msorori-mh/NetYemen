import '../domain/entities.dart';

const supportStatusLabels = <String, String>{
  'open': 'مفتوحة',
  'assigned': 'تم إسنادها',
  'in_progress': 'قيد المعالجة',
  'waiting_customer': 'بانتظار ردك',
  'resolved': 'تم الحل',
  'closed': 'مغلقة',
};

const supportTypeLabels = <String, String>{
  'ticket': 'تذكرة',
  'complaint': 'شكوى',
  'dispute': 'نزاع',
};

const supportCategoryLabels = <String, String>{
  'network': 'الشبكة',
  'package': 'الباقة',
  'service': 'الخدمة',
  'account': 'الحساب',
  'request': 'طلب إضافة شبكة',
  'other': 'أخرى',
};

const supportPriorityLabels = <String, String>{
  'low': 'منخفضة',
  'normal': 'عادية',
  'high': 'مرتفعة',
  'urgent': 'عاجلة',
};

const supportOutcomeLabels = <String, String>{
  'answered': 'تم الرد',
  'fixed': 'تم الإصلاح',
  'not_reproducible': 'تعذر إعادة المشكلة',
  'not_supported': 'خارج نطاق الدعم',
  'refund_recommended': 'موصى بالتعويض',
};

const supportEventLabels = <String, String>{
  'created': 'تم إنشاء التذكرة',
  'message_added': 'تمت إضافة رسالة',
  'assigned': 'تم إسناد التذكرة',
  'status_changed': 'تم تحديث الحالة',
  'internal_note_added': 'تمت إضافة ملاحظة داخلية',
  'reopened': 'أُعيد فتح التذكرة',
};

String supportStatusLabel(String value) =>
    supportStatusLabels[value] ?? 'حالة غير معروفة';

String supportTypeLabel(SupportCaseType value) =>
    supportTypeLabels[value.name] ?? 'طلب دعم';

String supportCategoryLabel(String value) =>
    supportCategoryLabels[value] ?? 'أخرى';

String supportPriorityLabel(String value) =>
    supportPriorityLabels[value] ?? 'عادية';

String supportOutcomeLabel(String value) =>
    supportOutcomeLabels[value] ?? 'نتيجة أخرى';

String supportEventLabel(String value) =>
    supportEventLabels[value] ?? 'تحديث على التذكرة';

String formatSupportDate(DateTime value) {
  final local = value.toLocal();
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${twoDigits(local.day)}/${twoDigits(local.month)}/${local.year}، '
      '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
}

String supportEventTransition(SupportEvent event) {
  final from = event.fromStatus;
  final to = event.toStatus;
  if (from != null && to != null) {
    return '${supportStatusLabel(from)} ← ${supportStatusLabel(to)}';
  }
  if (to != null) return supportStatusLabel(to);
  return '';
}
