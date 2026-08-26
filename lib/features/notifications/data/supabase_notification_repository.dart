import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/entities.dart';
import 'notification_repository.dart';

class SupabaseNotificationRepository implements NotificationRepository {
  final SupabaseClient _client;

  SupabaseNotificationRepository(this._client);

  @override
  Future<void> registerDeviceToken({
    required String platform,
    required String token,
    String? deviceFingerprint,
    String? appVersion,
  }) async {
    await _client.rpc<dynamic>(
      'register_device_push_token',
      params: {
        'p_platform': platform,
        'p_token': token,
        'p_device_fingerprint': deviceFingerprint,
        'p_app_version': appVersion,
      },
    );
  }

  @override
  Future<void> deactivateDeviceToken(String token) async {
    await _client.rpc<dynamic>(
      'deactivate_device_push_token',
      params: {'p_token': token},
    );
  }

  @override
  Future<NotificationPreferences> getPreferences() async {
    final result = await _client.rpc<Map<String, dynamic>>(
      'get_notification_preferences',
    );
    return NotificationPreferences.fromJson(result);
  }

  @override
  Future<NotificationPreferences> updatePreferences(
    NotificationPreferences prefs,
  ) async {
    final result = await _client.rpc<Map<String, dynamic>>(
      'update_notification_preferences',
      params: {
        'p_network_added_enabled': prefs.networkAddedEnabled,
        'p_package_added_enabled': prefs.packageAddedEnabled,
        'p_stock_restored_enabled': prefs.stockRestoredEnabled,
        'p_platform_updates_enabled': prefs.platformUpdatesEnabled,
        'p_offers_announcements_enabled': prefs.offersAnnouncementsEnabled,
      },
    );
    return NotificationPreferences.fromJson(result);
  }

  @override
  Future<List<InboxNotification>> listInbox({
    int limit = 50,
    bool unreadOnly = false,
  }) async {
    final result = await _client.rpc<List<dynamic>>(
      'list_my_notifications',
      params: {'p_limit': limit, 'p_unread_only': unreadOnly},
    );
    return result
        .map((row) => InboxNotification.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> markRead(String inboxId) async {
    await _client.rpc<dynamic>(
      'mark_notification_read',
      params: {'p_inbox_id': inboxId},
    );
  }

  @override
  Future<int> unreadCount() async {
    final result = await _client.rpc<dynamic>('get_unread_notification_count');
    if (result is int) return result;
    return int.tryParse('$result') ?? 0;
  }

  @override
  Future<TransportStatus> transportStatus() async {
    final result = await _client.rpc<Map<String, dynamic>>(
      'get_notification_transport_status',
    );
    return TransportStatus.fromJson(result);
  }

  @override
  Future<AdminComposeResult> adminCompose({
    required String titleAr,
    required String bodyAr,
    required String audienceType,
    Map<String, dynamic>? audiencePayload,
    String channelClass = 'announcement',
    String deepLink = 'notifications',
  }) async {
    final result = await _client.rpc<Map<String, dynamic>>(
      'admin_compose_notification',
      params: {
        'p_title_ar': titleAr,
        'p_body_ar': bodyAr,
        'p_audience_type': audienceType,
        'p_audience_payload': audiencePayload ?? <String, dynamic>{},
        'p_channel_class': channelClass,
        'p_deep_link': deepLink,
        'p_process_immediately': true,
      },
    );
    return AdminComposeResult.fromJson(result);
  }

  @override
  Future<Map<String, dynamic>> adminDeliverySummary(String eventId) async {
    final result = await _client.rpc<Map<String, dynamic>>(
      'admin_notification_delivery_summary',
      params: {'p_event_id': eventId},
    );
    return result;
  }
}
