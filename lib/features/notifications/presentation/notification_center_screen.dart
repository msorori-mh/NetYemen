import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../network_discovery/presentation/network_details_screen.dart';
import '../../network_discovery/presentation/network_discovery_providers.dart';
import '../../network_discovery/presentation/networks_list_screen.dart';
import '../../network_requests/presentation/my_requests_screen.dart';
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
            return const Center(
              child: Text('لا توجد إشعارات بعد'),
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
        error: (e, _) => Center(
          child: Text('تعذر تحميل الإشعارات: $e'),
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
            await ref.read(notificationRepositoryProvider).markRead(item.id);
            ref.invalidate(notificationInboxProvider);
            ref.invalidate(unreadNotificationCountProvider);
          }
          if (!context.mounted) return;
          await navigateNotificationDeepLink(context, ref, item.deepLink);
        },
      ),
    );
  }
}

Future<void> navigateNotificationDeepLink(
  BuildContext context,
  WidgetRef ref,
  String? deepLink,
) async {
  final target = ref.read(deepLinkParserProvider).parse(deepLink);
  switch (target.kind) {
    case DeepLinkKind.network:
      final networks = ref.read(networkCatalogProvider).valueOrNull ?? const [];
      final match = networks.where((n) => n.id == target.id).toList();
      if (match.isNotEmpty) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => NetworkDetailsScreen(network: match.first),
          ),
        );
      } else {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const NetworksListScreen()),
        );
      }
      break;
    case DeepLinkKind.package:
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _DeepLinkInfoScreen(
            title: 'باقة',
            message: target.id == null
                ? 'تعذر تحديد الباقة'
                : 'افتح كتالوج الشبكات للاطلاع على الباقة.',
          ),
        ),
      );
      break;
    case DeepLinkKind.request:
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const MyRequestsScreen()),
      );
      break;
    case DeepLinkKind.notifications:
      break;
    case DeepLinkKind.profile:
      Navigator.of(context).popUntil((route) => route.isFirst);
      break;
    case DeepLinkKind.unknown:
      break;
  }
}

class _DeepLinkInfoScreen extends StatelessWidget {
  final String title;
  final String message;

  const _DeepLinkInfoScreen({
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(message, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const NetworksListScreen()),
                );
              },
              child: const Text('عرض الشبكات'),
            ),
          ],
        ),
      ),
    );
  }
}
