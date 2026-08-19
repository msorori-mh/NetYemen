import '../domain/entities.dart';
import 'notification_repository.dart';

/// In-memory repository for demo mode and widget tests.
class FakeNotificationRepository implements NotificationRepository {
  NotificationPreferences _prefs = NotificationPreferences.defaults();
  final List<InboxNotification> _inbox = [];
  final Map<String, String> _tokens = {};
  int _composeSeq = 0;

  @override
  Future<void> registerDeviceToken({
    required String platform,
    required String token,
    String? deviceFingerprint,
    String? appVersion,
  }) async {
    if (token.contains('PRIVATE KEY') || token.contains('AIza')) {
      throw ArgumentError('SECRET_TOKEN_FORBIDDEN');
    }
    _tokens[token] = platform;
  }

  @override
  Future<void> deactivateDeviceToken(String token) async {
    _tokens.remove(token);
  }

  @override
  Future<NotificationPreferences> getPreferences() async => _prefs;

  @override
  Future<NotificationPreferences> updatePreferences(
    NotificationPreferences prefs,
  ) async {
    _prefs = prefs.copyWith(
      networkAddedEnabled: prefs.networkAddedEnabled,
      packageAddedEnabled: prefs.packageAddedEnabled,
      stockRestoredEnabled: prefs.stockRestoredEnabled,
      platformUpdatesEnabled: prefs.platformUpdatesEnabled,
      offersAnnouncementsEnabled: prefs.offersAnnouncementsEnabled,
    );
    return _prefs;
  }

  @override
  Future<List<InboxNotification>> listInbox({
    int limit = 50,
    bool unreadOnly = false,
  }) async {
    final items = unreadOnly ? _inbox.where((e) => !e.isRead) : _inbox;
    return items.take(limit).toList();
  }

  @override
  Future<void> markRead(String inboxId) async {
    final idx = _inbox.indexWhere((e) => e.id == inboxId);
    if (idx < 0) throw StateError('NOT_FOUND');
    final old = _inbox[idx];
    _inbox[idx] = InboxNotification(
      id: old.id,
      eventId: old.eventId,
      titleAr: old.titleAr,
      bodyAr: old.bodyAr,
      deepLink: old.deepLink,
      category: old.category,
      channelClass: old.channelClass,
      isRead: true,
      createdAt: old.createdAt,
    );
  }

  @override
  Future<int> unreadCount() async => _inbox.where((e) => !e.isRead).length;

  @override
  Future<TransportStatus> transportStatus() async => const TransportStatus(
    providerKey: 'unbound',
    bindingStatus: 'unbound',
    adapterInterface: 'NotificationTransportAdapter',
    externalPushDispatchEnabled: false,
  );

  @override
  Future<AdminComposeResult> adminCompose({
    required String titleAr,
    required String bodyAr,
    required String audienceType,
    Map<String, dynamic>? audiencePayload,
    String channelClass = 'announcement',
    String deepLink = 'notifications',
  }) async {
    final secretPattern = RegExp(
      r'(كلمة\s*المرور|باسورد|password|pin\b|card\s*code|voucher|cvv|secret)',
      caseSensitive: false,
    );
    if (secretPattern.hasMatch(titleAr) || secretPattern.hasMatch(bodyAr)) {
      throw ArgumentError('SECRET_PAYLOAD_FORBIDDEN');
    }
    _composeSeq += 1;
    final eventId = 'compose-$_composeSeq';
    _inbox.insert(
      0,
      InboxNotification(
        id: 'inbox-$_composeSeq',
        eventId: eventId,
        titleAr: titleAr,
        bodyAr: bodyAr,
        deepLink: deepLink,
        category: 'engagement',
        channelClass: channelClass,
        isRead: false,
        createdAt: DateTime.now(),
      ),
    );
    return AdminComposeResult(
      eventId: eventId,
      titleAr: titleAr,
      bodyAr: bodyAr,
      audienceType: audienceType,
    );
  }

  @override
  Future<Map<String, dynamic>> adminDeliverySummary(String eventId) async {
    return {
      'event_id': eventId,
      'total_deliveries': _inbox.where((e) => e.eventId == eventId).length,
      'transport': {'binding_status': 'unbound', 'provider_key': 'unbound'},
    };
  }

  void seedInbox(InboxNotification item) => _inbox.add(item);
}
