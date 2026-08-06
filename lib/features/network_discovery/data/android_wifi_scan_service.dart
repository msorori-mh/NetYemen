import 'dart:io';
import 'package:wifi_scan/wifi_scan.dart';
import '../../../core/error/app_exceptions.dart';
import 'wifi_scan_service.dart';

class AndroidWifiScanService implements WifiScanService {
  @override
  Future<bool> get isSupported async {
    if (!Platform.isAndroid) return false;
    return await WiFiScan.instance.isSupported();
  }

  @override
  Future<List<String>> performScan() async {
    if (!Platform.isAndroid) {
      throw const ScanUnsupportedException();
    }

    final supported = await WiFiScan.instance.isSupported();
    if (!supported) {
      throw const ScanUnsupportedException();
    }

    final canScan = await WiFiScan.instance.canGetScanResult();
    if (!canScan) {
      throw const ScanPermissionDeniedException();
    }

    final count = await WiFiScan.instance.startScan();
    if (count < 0) {
      throw const ScanException('فشل بدء المسح', code: 'SCAN_FAILED');
    }

    final scanResults = await WiFiScan.instance.getScanResults();
    final ssids = <String>{};

    for (final result in scanResults) {
      final ssid = result.ssid;
      if (ssid == null || ssid.isEmpty || ssid == '<unknown ssid>') continue;
      ssids.add(ssid);
    }

    return ssids.toList();
  }
}
