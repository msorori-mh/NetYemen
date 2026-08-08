/// Notification domain entities — provider-neutral; no transport secrets.
library;

enum NotificationCategory { transactional, engagement }

enum NotificationChannelClass {
  requestStatus,
  networkAdded,
  packageAdded,
  stockRestored,
  platformUpdate,
  announcement,
  offer,
}

class NotificationPreferences {
  final bool transactionalEnabled;
  final bool networkAddedEnabled;
  final bool packageAddedEnabled;
  final bool stockRestoredEnabled;
  final bool platformUpdatesEnabled;
  final bool offersAnnouncementsEnabled;

  const NotificationPreferences({
    required this.transactionalEnabled,
    required this.networkAddedEnabled,
    required this.packageAddedEnabled,
    required this.stockRestoredEnabled,
    required this.platformUpdatesEnabled,
    required this.offersAnnouncementsEnabled,
  });

  factory NotificationPreferences.defaults() => const NotificationPreferences(
        transactionalEnabled: true,
        networkAddedEnabled: true,
        packageAddedEnabled: true,
        stockRestoredEnabled: true,
        platformUpdatesEnabled: true,
        offersAnnouncementsEnabled: true,
      );

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    return NotificationPreferences(
      transactionalEnabled: json['transactional_enabled'] as bool? ?? true,
      networkAddedEnabled: json['network_added_enabled'] as bool? ?? true,
      packageAddedEnabled: json['package_added_enabled'] as bool? ?? true,
      stockRestoredEnabled: json['stock_restored_enabled'] as bool? ?? true,
      platformUpdatesEnabled: json['platform_updates_enabled'] as bool? ?? true,
      offersAnnouncementsEnabled:
          json['offers_announcements_enabled'] as bool? ?? true,
    );
  }

  NotificationPreferences copyWith({
    bool? networkAddedEnabled,
    bool? packageAddedEnabled,
    bool? stockRestoredEnabled,
    bool? platformUpdatesEnabled,
    bool? offersAnnouncementsEnabled,
  }) {
    return NotificationPreferences(
      transactionalEnabled: true,
      networkAddedEnabled: networkAddedEnabled ?? this.networkAddedEnabled,
      packageAddedEnabled: packageAddedEnabled ?? this.packageAddedEnabled,
      stockRestoredEnabled: stockRestoredEnabled ?? this.stockRestoredEnabled,
      platformUpdatesEnabled:
          platformUpdatesEnabled ?? this.platformUpdatesEnabled,
      offersAnnouncementsEnabled:
          offersAnnouncementsEnabled ?? this.offersAnnouncementsEnabled,
    );
  }
}

class InboxNotification {
  final String id;
  final String eventId;
  final String titleAr;
  final String bodyAr;
  final String? deepLink;
  final String category;
  final String channelClass;
  final bool isRead;
  final DateTime createdAt;

  const InboxNotification({
    required this.id,
    required this.eventId,
    required this.titleAr,
    required this.bodyAr,
    required this.deepLink,
    required this.category,
    required this.channelClass,
    required this.isRead,
    required this.createdAt,
  });

  factory InboxNotification.fromJson(Map<String, dynamic> json) {
    return InboxNotification(
      id: json['id'] as String,
      eventId: json['event_id'] as String,
      titleAr: json['title_ar'] as String,
      bodyAr: json['body_ar'] as String,
      deepLink: json['deep_link'] as String?,
      category: json['category'] as String,
      channelClass: json['channel_class'] as String,
      isRead: json['is_read'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class AdminComposeResult {
  final String eventId;
  final String titleAr;
  final String bodyAr;
  final String audienceType;

  const AdminComposeResult({
    required this.eventId,
    required this.titleAr,
    required this.bodyAr,
    required this.audienceType,
  });

  factory AdminComposeResult.fromJson(Map<String, dynamic> json) {
    return AdminComposeResult(
      eventId: json['event_id'] as String,
      titleAr: json['title_ar'] as String,
      bodyAr: json['body_ar'] as String,
      audienceType: json['audience_type'] as String,
    );
  }
}

class TransportStatus {
  final String providerKey;
  final String bindingStatus;
  final String adapterInterface;
  final bool externalPushDispatchEnabled;

  const TransportStatus({
    required this.providerKey,
    required this.bindingStatus,
    required this.adapterInterface,
    required this.externalPushDispatchEnabled,
  });

  factory TransportStatus.fromJson(Map<String, dynamic> json) {
    return TransportStatus(
      providerKey: json['provider_key'] as String? ?? 'unbound',
      bindingStatus: json['binding_status'] as String? ?? 'unbound',
      adapterInterface:
          json['adapter_interface'] as String? ?? 'NotificationTransportAdapter',
      externalPushDispatchEnabled:
          json['external_push_dispatch_enabled'] as bool? ?? false,
    );
  }

  bool get isUnbound => bindingStatus == 'unbound';
}
