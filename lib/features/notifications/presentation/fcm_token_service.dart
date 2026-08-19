// lib/features/notifications/presentation/fcm_token_service.dart

import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../providers/app_providers.dart';
import '../data/notification_repository.dart';
import 'notification_providers.dart';

/// Registers and refreshes the device FCM token with the backend.
///
/// This service does not embed any server secrets; it only interacts with the
/// local Firebase Messaging SDK and the Supabase notification repository.
class FcmTokenService {
  final NotificationRepository _repository;
  StreamSubscription<String>? _tokenRefreshSubscription;

  FcmTokenService({required NotificationRepository repository})
    : _repository = repository;

  /// Ensures Android notification permission is granted, then fetches and
  /// registers the current FCM token. Also starts listening for token refreshes.
  Future<void> initialize() async {
    try {
      await _tokenRefreshSubscription?.cancel();
      _tokenRefreshSubscription = null;
      await _requestPermission();
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await _registerToken(token);
      }
      _tokenRefreshSubscription = FirebaseMessaging.instance.onTokenRefresh
          .listen(
            _registerToken,
            onError: (Object error) {
              developer.log(
                'FCM token refresh stream error: $error',
                name: 'FcmTokenService',
              );
            },
          );
    } catch (e) {
      // Firebase may not be initialized in unconfigured/demo builds.
      developer.log('FCM initialization skipped: $e', name: 'FcmTokenService');
    }
  }

  /// Stops refresh handling and unlinks the current device token from the
  /// signed-out account. The local Firebase token is intentionally retained so
  /// it can be registered again after the next successful sign-in.
  Future<void> stop({bool deactivateToken = false}) async {
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;

    if (!deactivateToken) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await _repository.deactivateDeviceToken(token);
      }
    } catch (e) {
      developer.log(
        'FCM token deactivation skipped: $e',
        name: 'FcmTokenService',
      );
    }
  }

  /// Disposes the token-refresh listener.
  void dispose() {
    _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
  }

  Future<void> _requestPermission() async {
    if (Platform.isAndroid) {
      final status = await Permission.notification.status;
      if (status.isDenied || status.isRestricted) {
        await Permission.notification.request();
      }
    }
  }

  Future<void> _registerToken(String token) async {
    try {
      await _repository.registerDeviceToken(platform: 'android', token: token);
      developer.log('FCM token registered', name: 'FcmTokenService');
    } catch (e) {
      developer.log(
        'FCM token registration failed: $e',
        name: 'FcmTokenService',
      );
    }
  }
}

/// Riverpod provider for the FCM token service lifecycle.
final fcmTokenServiceProvider = Provider<FcmTokenService>((ref) {
  final repository = ref.watch(notificationRepositoryProvider);
  return FcmTokenService(repository: repository);
});

/// Initializes the FCM service once the app config is available.
///
/// Call this from a top-level widget (e.g. [AppShell]) after authentication is
/// ready. In demo/unconfigured mode the service silently no-ops.
class FcmTokenInitializer extends ConsumerStatefulWidget {
  final Widget child;

  const FcmTokenInitializer({super.key, required this.child});

  @override
  ConsumerState<FcmTokenInitializer> createState() =>
      _FcmTokenInitializerState();
}

class _FcmTokenInitializerState extends ConsumerState<FcmTokenInitializer> {
  FcmTokenService? _service;
  ProviderSubscription<User?>? _authSubscription;
  String? _activeUserId;

  @override
  void initState() {
    super.initState();
    try {
      _service = ref.read(fcmTokenServiceProvider);
      _authSubscription = ref.listenManual<User?>(
        currentUserProvider,
        (previous, next) => _syncWithAuthState(previous?.id, next?.id),
        fireImmediately: true,
      );
    } catch (e) {
      // Supabase or Firebase may not be initialized in tests/unconfigured builds.
      developer.log(
        'FCM token initializer skipped: $e',
        name: 'FcmTokenService',
      );
    }
  }

  void _syncWithAuthState(String? previousUserId, String? userId) {
    if (userId == _activeUserId) return;

    _activeUserId = userId;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (userId == null) {
        if (previousUserId != null) {
          await _service?.stop(deactivateToken: true);
        }
        return;
      }
      await _service?.initialize();
    });
  }

  @override
  void dispose() {
    _authSubscription?.close();
    _service?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
