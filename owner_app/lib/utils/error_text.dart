// lib/utils/error_text.dart
import 'dart:async';
import 'dart:developer' as developer;

import 'package:supabase_flutter/supabase_flutter.dart';

/// رسالة عامة تُعرض حين لا نعرف سبب الخطأ.
const String genericErrorText = 'حدث خطأ غير متوقع. حاول مرة أخرى.';

/// رسالة انقطاع الاتصال.
const String networkErrorText =
    'تعذّر الاتصال بالخادم. تحقّق من اتصالك بالإنترنت وحاول مرة أخرى.';

const Map<String, String> _knownCodes = {
  'UNAUTHENTICATED': 'انتهت جلستك. سجّل الدخول من جديد.',
  'AUTH_REQUIRED': 'انتهت جلستك. سجّل الدخول من جديد.',
  'FORBIDDEN_ROLE': 'حسابك لا يملك صلاحية تنفيذ هذا الإجراء.',
  'FORBIDDEN_VERIFICATION': 'هذا الإجراء يحتاج اعتماد إدارة واصل نت.',
  'INACTIVE_PROFILE': 'حسابك غير مفعّل. تواصل مع فريق واصل نت.',
  'NOT_FOUND': 'العنصر المطلوب غير موجود أو لم يعد متاحاً.',
  'INVALID_CARD':
      'يوجد رقم كرت غير صالح (فارغ، أطول من 64 خانة، أو يحتوي مسافات).',
  'INVALID_CARDS': 'قائمة الكروت غير صالحة. راجعها وحاول مرة أخرى.',
  'TOO_MANY_CARDS': 'الحد الأقصى للدفعة الواحدة 5000 كرت.',
  'INVALID_PRICE': 'السعر غير صالح. أدخل مبلغاً صحيحاً بالريال.',
  'INVALID_NAME': 'الاسم غير صالح.',
  'INVALID_STATE': 'لا يمكن تنفيذ هذا الإجراء في الحالة الحالية.',
  'INVALID_STATUS': 'لا يمكن تنفيذ هذا الإجراء في الحالة الحالية.',
  'INVALID_TRANSITION': 'لا يمكن تنفيذ هذا الإجراء في الحالة الحالية.',
  'INVALID_PACKAGE_REFERENCE': 'الباقة المختارة لا تتبع هذه الشبكة.',
  'INVALID_PIN': 'رمز الدخول يجب أن يتكوّن من 6 أرقام.',
  'PIN_ALREADY_SET': 'رمز الدخول مضبوط مسبقاً لهذا الحساب.',
  'PIN_NOT_SET': 'لم يُضبط رمز دخول لهذا الحساب بعد.',
  'PIN_LOCKED':
      'تم حظر الحساب مؤقتاً بسبب المحاولات الخاطئة. حاول بعد 15 دقيقة.',
  'SSID_TOO_LONG': 'اسم الشبكة (SSID) أطول من المسموح.',
  'RATE_LIMITED': 'محاولات كثيرة. انتظر قليلاً ثم حاول مرة أخرى.',
};

final RegExp _leadingCode = RegExp(r'^([A-Z][A-Z0-9_]{2,})\b');

String _rawMessage(Object error) {
  if (error is PostgrestException) return error.message;
  if (error is AuthException) return error.message;
  return error.toString();
}

bool _looksLikeNetworkError(Object error, String message) {
  if (error is TimeoutException) return true;
  final haystack = '${error.runtimeType} $message'.toLowerCase();
  return haystack.contains('socketexception') ||
      haystack.contains('clientexception') ||
      haystack.contains('failed host lookup') ||
      haystack.contains('connection refused') ||
      haystack.contains('connection closed') ||
      haystack.contains('connection reset') ||
      haystack.contains('network is unreachable') ||
      haystack.contains('handshakeexception') ||
      haystack.contains('authretryablefetch') ||
      haystack.contains('timed out');
}

/// يحوّل أي استثناء إلى رسالة عربية آمنة للعرض.
///
/// دالة نقية: لا تُظهر نص الاستثناء الخام أبداً. الأكواد المعروفة من الخادم
/// (مثل `FORBIDDEN_ROLE: ...`) تُترجم، وما عداها يعود إلى [fallback].
String friendlyErrorText(Object error, {String fallback = genericErrorText}) {
  final message = _rawMessage(error).trim();

  final code = _leadingCode.firstMatch(message)?.group(1);
  if (code != null) {
    final known = _knownCodes[code];
    if (known != null) return known;
    if (code.startsWith('INVALID_')) {
      return 'البيانات المدخلة غير صالحة. راجعها وحاول مرة أخرى.';
    }
    if (code.startsWith('FORBIDDEN')) {
      return 'حسابك لا يملك صلاحية تنفيذ هذا الإجراء.';
    }
  }

  if (error is PostgrestException) {
    switch (error.code) {
      case '23505':
        return 'هذا العنصر موجود مسبقاً.';
      case '23514':
      case '23502':
      case '22001':
        return 'البيانات المدخلة غير صالحة. راجعها وحاول مرة أخرى.';
      case '42501':
        return 'حسابك لا يملك صلاحية تنفيذ هذا الإجراء.';
      case 'PGRST301':
        return 'انتهت جلستك. سجّل الدخول من جديد.';
    }
  }

  if (_looksLikeNetworkError(error, message)) return networkErrorText;

  return fallback;
}

/// يسجّل تفاصيل الخطأ للمطوّر (dart:developer) ويعيد الرسالة الآمنة للعرض.
String describeError(
  Object error, {
  StackTrace? stackTrace,
  String where = 'owner',
  String fallback = genericErrorText,
}) {
  developer.log(
    'Operation failed',
    name: where,
    error: error,
    stackTrace: stackTrace,
  );
  return friendlyErrorText(error, fallback: fallback);
}
