import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Android 13+ notification permission UX without binding a push provider SDK.
class NotificationPermissionService {
  const NotificationPermissionService();

  Future<NotificationPermissionState> currentState() async {
    if (kIsWeb) return NotificationPermissionState.unsupported;
    if (!Platform.isAndroid) return NotificationPermissionState.unsupported;

    final status = await Permission.notification.status;
    if (status.isGranted) return NotificationPermissionState.granted;
    if (status.isPermanentlyDenied) {
      return NotificationPermissionState.permanentlyDenied;
    }
    if (status.isDenied) return NotificationPermissionState.denied;
    return NotificationPermissionState.unknown;
  }

  Future<NotificationPermissionState> request() async {
    if (kIsWeb) return NotificationPermissionState.unsupported;
    if (!Platform.isAndroid) return NotificationPermissionState.unsupported;

    final status = await Permission.notification.request();
    if (status.isGranted) return NotificationPermissionState.granted;
    if (status.isPermanentlyDenied) {
      return NotificationPermissionState.permanentlyDenied;
    }
    return NotificationPermissionState.denied;
  }

  Future<bool> openSystemSettings() => openAppSettings();
}

enum NotificationPermissionState {
  granted,
  denied,
  permanentlyDenied,
  unsupported,
  unknown,
}
