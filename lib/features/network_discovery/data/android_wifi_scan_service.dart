import 'dart:io';

import 'package:wifi_scan/wifi_scan.dart';

import '../../../core/error/app_exceptions.dart';
import 'wifi_scan_service.dart';

/// Android implementation of [WifiScanService].
///
/// This service triggers an explicit foreground Wi-Fi scan and returns only
/// SSID strings. It never persists or transmits BSSID, MAC addresses, signal
/// strength, frequency, or location data.
class AndroidWifiScanService implements WifiScanService {
  @override
  Future<bool> get isSupported async {
    if (!Platform.isAndroid) return false;
    final can = await WiFiScan.instance.canStartScan(askPermissions: false);
    return can != CanStartScan.notSupported;
  }

  @override
  Future<List<String>> performScan() async {
    if (!Platform.isAndroid) {
      throw const ScanUnsupportedException();
    }

    final canStart = await WiFiScan.instance.canStartScan(askPermissions: true);
    _assertCanStart(canStart);

    final started = await WiFiScan.instance.startScan();
    if (!started) {
      // On Android, startScan frequently returns false when throttled.
      throw const ScanThrottledException();
    }

    final canGet = await WiFiScan.instance.canGetScannedResults(
      askPermissions: true,
    );
    _assertCanGetResults(canGet);

    final results = await WiFiScan.instance.getScannedResults();
    final ssids = <String>{};

    for (final accessPoint in results) {
      final ssid = accessPoint.ssid.trim();
      if (ssid.isEmpty || ssid == '<unknown ssid>') continue;
      ssids.add(ssid);
    }

    return ssids.toList();
  }

  void _assertCanStart(CanStartScan can) {
    switch (can) {
      case CanStartScan.yes:
        return;
      case CanStartScan.notSupported:
        throw const ScanUnsupportedException();
      case CanStartScan.noLocationPermissionRequired:
      case CanStartScan.noLocationPermissionDenied:
      case CanStartScan.noLocationPermissionUpgradeAccuracy:
        throw const ScanPermissionDeniedException();
      case CanStartScan.noLocationServiceDisabled:
        throw const WifiDisabledException();
      case CanStartScan.failed:
        throw const ScanException(
          'تعذّر بدء المسح',
          code: 'SCAN_FAILED',
        );
    }
  }

  void _assertCanGetResults(CanGetScannedResults can) {
    switch (can) {
      case CanGetScannedResults.yes:
        return;
      case CanGetScannedResults.notSupported:
        throw const ScanUnsupportedException();
      case CanGetScannedResults.noLocationPermissionRequired:
      case CanGetScannedResults.noLocationPermissionDenied:
      case CanGetScannedResults.noLocationPermissionUpgradeAccuracy:
        throw const ScanPermissionDeniedException();
      case CanGetScannedResults.noLocationServiceDisabled:
        throw const WifiDisabledException();
    }
  }
}
