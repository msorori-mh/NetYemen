import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/features/support/domain/entities.dart';
import 'package:netyemen/features/support/presentation/support_display.dart';

void main() {
  test('customer-facing support values are localized safely', () {
    expect(supportTypeLabel(SupportCaseType.complaint), 'شكوى');
    expect(supportCategoryLabel('network'), 'الشبكة');
    expect(supportPriorityLabel('urgent'), 'عاجلة');
    expect(supportStatusLabel('waiting_customer'), 'بانتظار ردك');
    expect(supportOutcomeLabel('refund_recommended'), 'موصى بالتعويض');

    expect(supportCategoryLabel('future_category'), 'أخرى');
    expect(supportStatusLabel('future_status'), 'حالة غير معروفة');
  });

  test('support event transition never exposes raw status codes', () {
    final event = SupportEvent(
      eventType: 'status_changed',
      fromStatus: 'assigned',
      toStatus: 'waiting_customer',
      createdAt: DateTime.utc(2026, 9, 19, 20, 5),
    );

    expect(supportEventLabel(event.eventType), 'تم تحديث الحالة');
    expect(supportEventTransition(event), 'تم إسنادها ← بانتظار ردك');
    expect(supportEventTransition(event), isNot(contains('waiting_customer')));
  });

  test('support date uses a compact deterministic customer format', () {
    final value = DateTime(2026, 9, 3, 7, 5);

    expect(formatSupportDate(value), '03/09/2026، 07:05');
  });
}
