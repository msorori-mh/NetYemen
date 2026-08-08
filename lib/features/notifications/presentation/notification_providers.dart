import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../network_discovery/presentation/network_discovery_providers.dart';
import '../data/fake_notification_repository.dart';
import '../data/notification_repository.dart';
import '../data/notification_transport_adapter.dart';
import '../data/supabase_notification_repository.dart';
import '../domain/entities.dart';
import '../deep_link/deep_link_parser.dart';
import 'notification_permission_service.dart';

final notificationTransportAdapterProvider =
    Provider<NotificationTransportAdapter>((ref) {
  return const UnboundNotificationTransportAdapter();
});

final deepLinkParserProvider = Provider<DeepLinkParser>((ref) {
  return const DeepLinkParser();
});

final notificationPermissionServiceProvider =
    Provider<NotificationPermissionService>((ref) {
  return const NotificationPermissionService();
});

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  final config = ref.watch(appConfigProvider);
  if (config.isDemoMode || !config.isConfigured) {
    return FakeNotificationRepository();
  }
  return SupabaseNotificationRepository(Supabase.instance.client);
});

final notificationPreferencesProvider =
    FutureProvider<NotificationPreferences>((ref) async {
  final repo = ref.watch(notificationRepositoryProvider);
  return repo.getPreferences();
});

final notificationInboxProvider =
    FutureProvider<List<InboxNotification>>((ref) async {
  final repo = ref.watch(notificationRepositoryProvider);
  return repo.listInbox();
});

final unreadNotificationCountProvider = FutureProvider<int>((ref) async {
  final repo = ref.watch(notificationRepositoryProvider);
  return repo.unreadCount();
});

final transportStatusProvider = FutureProvider<TransportStatus>((ref) async {
  final repo = ref.watch(notificationRepositoryProvider);
  return repo.transportStatus();
});

/// Foreground in-app banner payload (no external provider required).
class ForegroundNotificationBanner {
  final String title;
  final String body;
  final String? deepLink;

  const ForegroundNotificationBanner({
    required this.title,
    required this.body,
    this.deepLink,
  });
}

final foregroundBannerProvider =
    StateProvider<ForegroundNotificationBanner?>((ref) => null);
