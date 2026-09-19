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
    return PushMessage(
      messageId: message.messageId,
      title: message.notification?.title ??
          data['title_ar']?.toString() ??
          data['title']?.toString() ??
          'إشعار جديد',
      body: message.notification?.body ??
          data['body_ar']?.toString() ??
          data['body']?.toString() ??
          'لديك تحديث جديد في واصل نت.',
      deepLink:
          data['deep_link']?.toString() ?? data['deepLink']?.toString(),
    );
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
