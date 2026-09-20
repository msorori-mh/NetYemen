import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/push_message_source.dart';
import 'notification_center_screen.dart';
import 'notification_providers.dart';

class PushMessageListener extends ConsumerStatefulWidget {
  final Widget child;

  const PushMessageListener({super.key, required this.child});

  @override
  ConsumerState<PushMessageListener> createState() =>
      _PushMessageListenerState();
}

class _PushMessageListenerState extends ConsumerState<PushMessageListener> {
  static const _maximumRememberedMessages = 50;

  final Queue<String> _openedMessageOrder = Queue<String>();
  final Set<String> _openedMessageKeys = <String>{};
  StreamSubscription<PushMessage>? _foregroundSubscription;
  StreamSubscription<PushMessage>? _openedSubscription;

  @override
  void initState() {
    super.initState();
    try {
      final source = ref.read(pushMessageSourceProvider);
      _foregroundSubscription = source.foregroundMessages.listen(
        _handleForegroundMessage,
        onError: _logStreamError,
      );
      _openedSubscription = source.openedMessages.listen(
        _handleOpenedMessage,
        onError: _logStreamError,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        try {
          final initialMessage = await source.getInitialMessage();
          if (initialMessage != null && mounted) {
            await _handleOpenedMessage(initialMessage);
          }
        } catch (error) {
          _logError('FCM initial message unavailable', error);
        }
      });
    } catch (error) {
      _logError('FCM message listener skipped', error);
    }
  }

  void _handleForegroundMessage(PushMessage message) {
    if (!mounted) return;
    _refreshInbox();
    ref.read(foregroundBannerProvider.notifier).state =
        ForegroundNotificationBanner(
      title: message.title,
      body: message.body,
      deepLink: message.deepLink,
    );

    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const Key('foreground-push-message'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message.title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(message.body),
            ],
          ),
          action: message.deepLink == null
              ? null
              : SnackBarAction(
                  label: 'فتح',
                  onPressed: () => _openDeepLink(message.deepLink),
                ),
        ),
      );
  }

  Future<void> _handleOpenedMessage(PushMessage message) async {
    if (!mounted || !_rememberOpenedMessage(message.deduplicationKey)) return;
    _refreshInbox();
    await _openDeepLink(message.deepLink);
  }

  bool _rememberOpenedMessage(String key) {
    if (_openedMessageKeys.contains(key)) return false;
    _openedMessageKeys.add(key);
    _openedMessageOrder.addLast(key);
    if (_openedMessageOrder.length > _maximumRememberedMessages) {
      _openedMessageKeys.remove(_openedMessageOrder.removeFirst());
    }
    return true;
  }

  void _refreshInbox() {
    ref.invalidate(notificationInboxProvider);
    ref.invalidate(unreadNotificationCountProvider);
  }

  Future<void> _openDeepLink(String? deepLink) async {
    if (!mounted || deepLink == null || deepLink.trim().isEmpty) return;
    await navigateNotificationDeepLink(context, ref, deepLink);
  }

  void _logStreamError(Object error, StackTrace stackTrace) {
    _logError('FCM message stream error', error, stackTrace);
  }

  void _logError(String message, Object error, [StackTrace? stackTrace]) {
    developer.log(
      '$message: $error',
      name: 'PushMessageListener',
      stackTrace: stackTrace,
    );
  }

  @override
  void dispose() {
    _foregroundSubscription?.cancel();
    _openedSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
