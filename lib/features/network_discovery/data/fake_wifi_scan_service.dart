import '../../../core/error/app_exceptions.dart';
import 'wifi_scan_service.dart';

class FakeWifiScanService implements WifiScanService {
  final List<String> _fakeSsids;
  final bool supported;
  final bool shouldThrow;
  final String? throwCode;

  FakeWifiScanService({
    List<String> fakeSsids = const [],
    this.supported = true,
    this.shouldThrow = false,
    this.throwCode,
  }) : _fakeSsids = fakeSsids;

  @override
  Future<bool> get isSupported async => supported;

  @override
  Future<List<String>> performScan() async {
    if (!supported) throw const ScanUnsupportedException();
    if (shouldThrow) {
      switch (throwCode) {
        case 'SCAN_PERMISSION_DENIED':
          throw const ScanPermissionDeniedException();
        case 'SCAN_THROTTLED':
          throw const ScanThrottledException();
        case 'WIFI_DISABLED':
          throw const WifiDisabledException();
        default:
          throw const ScanException('فشل المسح', code: 'SCAN_FAILED');
      }
    }
    await Future.delayed(const Duration(milliseconds: 100));
    return List.of(_fakeSsids);
  }
}
