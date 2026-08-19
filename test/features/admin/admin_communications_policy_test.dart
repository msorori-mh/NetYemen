import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/features/notifications/domain/admin_notification_policy.dart';
import 'package:netyemen/features/support/domain/support_operation_policy.dart';

void main() {
  group('AdminNotificationPolicy', () {
    test('accepts a complete broadcast', () {
      expect(
        AdminNotificationPolicy.validate(
          title: 'تحديث',
          body: 'تم تحديث المنصة.',
          audienceType: 'all_active_customers',
          audienceValue: '',
        ),
        isNull,
      );
    });

    test('requires a targeted audience value', () {
      expect(
        AdminNotificationPolicy.validate(
          title: 'تحديث',
          body: 'نص الإعلان',
          audienceType: 'specific_user',
          audienceValue: '',
        ),
        isNotNull,
      );
    });

    test('rejects an invalid target identifier', () {
      expect(
        AdminNotificationPolicy.validate(
          title: 'تحديث',
          body: 'نص الإعلان',
          audienceType: 'specific_user',
          audienceValue: 'not-a-uuid',
        ),
        'معرّف الجمهور غير صالح.',
      );
    });

    test('rejects unsupported roles', () {
      expect(
        AdminNotificationPolicy.validate(
          title: 'تحديث',
          body: 'نص الإعلان',
          audienceType: 'role_based',
          audienceValue: 'unknown_role',
        ),
        'الدور المحدد غير مدعوم.',
      );
    });
  });

  group('SupportOperationPolicy', () {
    test('requires a resolution before resolving', () {
      expect(
        SupportOperationPolicy.validateResolution('resolved', '  '),
        isNotNull,
      );
    });

    test('allows an in-progress update without resolution', () {
      expect(
        SupportOperationPolicy.validateResolution('in_progress', ''),
        isNull,
      );
    });

    test('normalizes optional workflow text', () {
      expect(SupportOperationPolicy.normalizeActionText('  تم الحل  '), 'تم الحل');
      expect(SupportOperationPolicy.normalizeActionText('   '), isNull);
    });
  });
}
