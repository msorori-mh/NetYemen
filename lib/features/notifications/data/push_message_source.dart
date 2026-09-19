import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PushMessage {
  final String? messageId;
  final String title;
  final String body;
  final String? deepLink;

  const PushMessage({
    this.messageId,
    required this.title,
    required this.body,
    this.deepLink,
  });

  factory PushMessage.fromRemoteMessage(RemoteMessage message) {
    final data = message.data;
    final title = _firstNonEmpty([
      message.notification?.title,
      data['title_ar'],
      data['title'],
    ]);
    final body = _firstNonEmpty([
      message.notification?.body,
      data['body_ar'],
      data['body'],
    ]);
    final deepLink = _firstNonEmpty([data['deep_link'], data['deepLink']]);
    return PushMessage(
      messageId: message.messageId,
      title: title ?? 'إشعار جديد',
      body: body ?? 'لديك تحديث جديد في واصل نت.',
      deepLink: deepLink,
    );
  }

  static String? _firstNonEmpty(List<Object?> values) {
    for (final value in values) {
      final text = value?.toString().trim();
      if (text != null && text.isNotEmpty) return text;
    }
    return null;
  }

  String get deduplicationKey =>
      messageId ?? '$title\u0000$body\u0000${deepLink ?? ''}';
}

abstract class PushMessageSource {
  Stream<PushMessage> get foregroundMessages;
  Stream<PushMessage> get openedMessages;
  Future<PushMessage?> getInitialMessage();
}

class FirebasePushMessageSource implements PushMessageSource {
  const FirebasePushMessageSource();

  @override
  Stream<PushMessage> get foregroundMessages =>
      FirebaseMessaging.onMessage.map(PushMessage.fromRemoteMessage);

  @override
  Stream<PushMessage> get openedMessages =>
      FirebaseMessaging.onMessageOpenedApp.map(PushMessage.fromRemoteMessage);

  @override
  Future<PushMessage?> getInitialMessage() async {
    final message = await FirebaseMessaging.instance.getInitialMessage();
    return message == null ? null : PushMessage.fromRemoteMessage(message);
  }
}

final pushMessageSourceProvider = Provider<PushMessageSource>((ref) {
  return const FirebasePushMessageSource();
});
