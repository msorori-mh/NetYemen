import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/features/network_discovery/data/android_wifi_scan_service.dart';
import 'package:netyemen/features/network_discovery/data/fake_wifi_scan_service.dart';
import 'package:netyemen/features/network_discovery/presentation/network_discovery_providers.dart';

void main() {
  test('Android uses hardware scan even when backend is in demo mode', () {
    expect(
      wifiScanServiceForPlatform(isAndroid: true),
      isA<AndroidWifiScanService>(),
    );
    expect(
      wifiScanServiceForPlatform(isAndroid: false),
      isA<FakeWifiScanService>(),
    );
  });

  test('Android manifest permits precise location for current SDKs', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(
      manifest,
      contains('android.permission.ACCESS_FINE_LOCATION'),
    );
    expect(
      manifest,
      isNot(contains('android:maxSdkVersion="32"')),
    );
  });
}
