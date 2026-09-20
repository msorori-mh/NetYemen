import '../domain/entities.dart';

abstract class NotificationRepository {
  Future<void> registerDeviceToken({
    required String platform,
    required String token,
    String? deviceFingerprint,
    String? appVersion,
  });

  Future<void> deactivateDeviceToken(String token);

  Future<NotificationPreferences> getPreferences();

  Future<NotificationPreferences> updatePreferences(
    NotificationPreferences prefs,
  );

  Future<List<InboxNotification>> listInbox({
    int limit = 50,
    bool unreadOnly = false,
  });

  Future<void> markRead(String inboxId);

  Future<int> unreadCount();

  Future<TransportStatus> transportStatus();

  Future<AdminComposeResult> adminCompose({
    required String titleAr,
    required String bodyAr,
    required String audienceType,
    Map<String, dynamic>? audiencePayload,
    String channelClass = 'announcement',
    String deepLink = 'notifications',
  });

  Future<Map<String, dynamic>> adminDeliverySummary(String eventId);
}
