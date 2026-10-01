// lib/utils/dev_config.dart
import 'package:flutter/foundation.dart';

/// إعدادات تسجيل دخول تجريبي للتطوير فقط.
///
/// القيم تُمرَّر وقت البناء عبر --dart-define ولا تُخزَّن في المستودع إطلاقاً
/// (المستودع عام، وأي رقم/رمز مكتوب فيه يصبح باباً خلفياً لأي شخص):
///
///   flutter run --dart-define=DEV_TEST_PHONE=7XXXXXXXX \
///               --dart-define=DEV_TEST_OTP=NNNNNN
///
/// حاجز الأمان: كل شيء هنا مقفل بـ [kReleaseMode]. حتى لو مرّر أحدهم
/// الـ defines إلى بناء release فستبقى القيم فارغة وتبقى [isEnabled] false،
/// فلا يمكن لهذا المسار أن يصل إلى المستخدمين.
class DevConfig {
  const DevConfig._();

  static const String _phone = String.fromEnvironment('DEV_TEST_PHONE');
  static const String _otp = String.fromEnvironment('DEV_TEST_OTP');

  /// مفعّل فقط في بناء debug/profile مع تمرير رقم تجريبي.
  static bool get isEnabled => !kReleaseMode && _phone.isNotEmpty;

  /// الرقم المحلي بدون مقدمة الدولة (9 أرقام)، مثل 7XXXXXXXX.
  static String get testPhone => isEnabled ? _phone : '';

  /// رمز التحقق التجريبي المطابق للمضبوط في Supabase Test OTP.
  static String get testOtp => kReleaseMode ? '' : _otp;
}
