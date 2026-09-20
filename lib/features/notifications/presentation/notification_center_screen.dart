import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../network_discovery/presentation/network_details_screen.dart';
import '../../network_discovery/presentation/network_discovery_providers.dart';
import '../../network_discovery/presentation/networks_list_screen.dart';
import '../../network_requests/presentation/my_requests_screen.dart';
import '../../packages/presentation/package_providers.dart';
import '../../profile/presentation/profile_screen.dart';
import '../deep_link/deep_link_parser.dart';
import '../domain/entities.dart';
import 'notification_providers.dart';

class NotificationCenterScreen extends ConsumerWidget {
  const NotificationCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inboxAsync = ref.watch(notificationInboxProvider);
    final unreadAsync = ref.watch(unreadNotificationCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('الإشعارات'),
        actions: [
          unreadAsync.when(
            data: (count) => count > 0
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Center(
                      child: Text(
                        '$count غير مقروء',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(notificationInboxProvider);
              ref.invalidate(unreadNotificationCountProvider);
            },
          ),
        ],
      ),
      body: inboxAsync.when(
        data: (items) {
          if (items.isEmpty) {
            return _NotificationState(
              icon: Icons.notifications_none_outlined,
              title: 'لا توجد إشعارات بعد',
              message: 'ستظهر هنا تحديثات الطلبات والمعاملات والشبكات.',
              actionLabel: 'تحديث',
              onAction: () {
                ref.invalidate(notificationInboxProvider);
                ref.invalidate(unreadNotificationCountProvider);
              },
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = items[index];
              return _InboxTile(item: item);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _NotificationState(
          icon: Icons.cloud_off_outlined,
          title: 'تعذر تحميل الإشعارات',
          message: 'تحقق من الاتصال ثم أعد المحاولة.',
          actionLabel: 'إعادة المحاولة',
          onAction: () {
            ref.invalidate(notificationInboxProvider);
            ref.invalidate(unreadNotificationCountProvider);
          },
        ),
      ),
    );
  }
}

class _InboxTile extends ConsumerWidget {
  final InboxNotification item;

  const _InboxTile({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      color: item.isRead
          ? AppTheme.surface
          : AppTheme.primary.withValues(alpha: 0.06),
      child: ListTile(
        leading: Icon(
          item.category == 'transactional'
              ? Icons.verified_outlined
              : Icons.campaign_outlined,
          color: AppTheme.primary,
        ),
        title: Text(
          item.titleAr,
          style: TextStyle(
            fontWeight: item.isRead ? FontWeight.w500 : FontWeight.bold,
          ),
        ),
        subtitle: Text(item.bodyAr),
        trailing: item.isRead
            ? null
            : const Icon(Icons.circle, size: 10, color: AppTheme.primary),
        onTap: () async {
          if (!item.isRead) {
            try {
              await ref.read(notificationRepositoryProvider).markRead(item.id);
              ref.invalidate(notificationInboxProvider);
              ref.invalidate(unreadNotificationCountProvider);
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'تعذر تحديث حالة القراءة. يمكنك متابعة فتح الإشعار.',
                    ),
                  ),
                );
              }
            }
          }
          if (!context.mounted) return;
          await navigateNotificationDeepLink(
            context,
            ref,
            item.deepLink,
            openNotificationCenter: false,
          );
        },
      ),
    );
  }
}

class _NotificationState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  const _NotificationState({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: AppTheme.textSecondary),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.refresh),
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> navigateNotificationDeepLink(
  BuildContext context,
  WidgetRef ref,
  String? deepLink, {
  bool openNotificationCenter = true,
}) async {
  final target = ref.read(deepLinkParserProvider).parse(deepLink);
  switch (target.kind) {
    case DeepLinkKind.network:
      await _openNetworkDestination(context, ref, target.id);
      break;
    case DeepLinkKind.package:
      final packageId = target.id;
      String? networkId;
      if (packageId != null && packageId.isNotEmpty) {
        try {
          final package =
              await ref.read(packageRepositoryProvider).fetchPackage(packageId);
          networkId = package?.networkId;
        } catch (_) {
          networkId = null;
        }
      }
      if (!context.mounted) return;
      await _openNetworkDestination(context, ref, networkId);
      break;
    case DeepLinkKind.request:
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const MyRequestsScreen()));
      break;
    case DeepLinkKind.notifications:
      if (openNotificationCenter) {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const NotificationCenterScreen()),
        );
      }
      break;
    case DeepLinkKind.profile:
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ProfileScreen()),
      );
      break;
    case DeepLinkKind.unknown:
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('تعذر فتح وجهة الإشعار.')),
      );
      break;
  }
}

Future<void> _openNetworkDestination(
  BuildContext context,
  WidgetRef ref,
  String? networkId,
) async {
  final cachedNetworks =
      ref.read(networkCatalogProvider).valueOrNull ?? const [];
  final cached = cachedNetworks.where((network) => network.id == networkId);
  var network = cached.isEmpty ? null : cached.first;

  if (network == null && networkId != null && networkId.isNotEmpty) {
    try {
      network = await ref
          .read(networkCatalogRepositoryProvider)
          .fetchNetworkDetail(networkId);
    } catch (_) {
      network = null;
    }
  }

  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => network == null
          ? const NetworksListScreen()
          : NetworkDetailsScreen(network: network),
    ),
  );
}
