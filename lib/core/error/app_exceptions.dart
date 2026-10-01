class AppException implements Exception {
  final String message;
  final String? code;

  const AppException(this.message, {this.code});

  @override
  String toString() => 'AppException($code): $message';
}

class NetworkException extends AppException {
  const NetworkException(super.message, {super.code});
}

class AuthRequiredException extends AppException {
  const AuthRequiredException()
      : super('تسجيل الدخول مطلوب', code: 'AUTH_REQUIRED');
}

class ScanException extends AppException {
  const ScanException(super.message, {super.code});
}

class ScanPermissionDeniedException extends ScanException {
  const ScanPermissionDeniedException()
      : super('تم رفض إذن المسح', code: 'SCAN_PERMISSION_DENIED');
}

class ScanUnsupportedException extends ScanException {
  const ScanUnsupportedException()
      : super('المسح غير مدعوم على هذا الجهاز', code: 'SCAN_UNSUPPORTED');
}

class ScanThrottledException extends ScanException {
  const ScanThrottledException()
      : super('تم تقييد المسح — حاول لاحقاً', code: 'SCAN_THROTTLED');
}

class WifiDisabledException extends ScanException {
  const WifiDisabledException()
      : super('الواي فاي غير مُفعّل', code: 'WIFI_DISABLED');
}
