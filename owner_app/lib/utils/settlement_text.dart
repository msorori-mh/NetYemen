// lib/utils/settlement_text.dart
//
// منطق نقي لعرض التسويات. دُفعة التسوية قد يكون صافيها سالباً (المرتجعات
// أكبر من المبيعات ⇒ المالك مدين)، وبنود المرتجعات صافيها سالب دائماً.
// أي حالة أو نوع غير معروف يُعرض كما هو ولا يرمي استثناءً.

/// يحوّل قيمة JSON (عدد، نص، أو null) إلى عدد صحيح؛ غير المفهوم = صفر.
int settlementAmount(Object? value) {
  if (value is num) return value.round();
  if (value is String) return num.tryParse(value.trim())?.round() ?? 0;
  return 0;
}

/// مبلغ يُعرض مطروحاً (عمولة، مرتجعات): `-500`، والصفر يبقى `0`.
String deductionText(Object? value) {
  final amount = settlementAmount(value).abs();
  return amount == 0 ? '0' : '-$amount';
}

/// هل صافي الدفعة سالب (المالك مدين للمنصة)؟
bool settlementOwnerOwes(Object? netSettlement) {
  return settlementAmount(netSettlement) < 0;
}

/// عنوان خانة الصافي بحسب إشارته.
String settlementNetLabel(Object? netSettlement) {
  return settlementOwnerOwes(netSettlement)
      ? 'الصافي المستحق عليك'
      : 'الصافي المستحق لك';
}

/// حالة دُفعة التسوية (`settlement_batches.status`).
String settlementStatusLabel(Object? status) {
  switch (status) {
    case 'paid':
      return 'مدفوعة';
    case 'approved':
      return 'معتمدة';
    case 'draft':
      return 'مسودة';
    case 'ready_for_review':
      return 'قيد المراجعة';
    case 'cancelled':
      return 'ملغاة';
    case 'corrected':
      return 'معدّلة';
    default:
      return status?.toString() ?? '—';
  }
}

/// نوع بند الدفعة (`settlement_batch_lines.line_type`).
String settlementLineTypeLabel(Object? lineType) {
  switch (lineType) {
    case 'sale':
      return 'بيع';
    case 'refund':
      return 'مرتجع';
    case 'adjustment':
      return 'تعديل';
    default:
      return lineType?.toString() ?? '—';
  }
}
