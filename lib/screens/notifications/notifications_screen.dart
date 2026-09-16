// lib/screens/notifications/notifications_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';
import '../../utils/app_theme.dart';

/// شاشة الإشعارات — تعرض إشعارات المستخدم من `list_my_notifications`.
///
/// الحقول المتوقعة (defensive): id/inbox_id, title_ar, body_ar, deep_link,
/// category, created_at, read_at/is_read. أي حقل مفقود يُتجاهل.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('الإشعارات'),
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all),
            tooltip: 'تأشير الكل كمقروء',
            onPressed: () async {
              final notifications = notificationsAsync.valueOrNull ?? [];
              final service = ref.read(supabaseServiceProvider);
              for (final n in notifications) {
                final isRead = n['is_read'] == true || n['read_at'] != null;
                if (!isRead) {
                  final id = (n['inbox_id'] ?? n['id'])?.toString();
                  if (id != null) {
                    try {
                      await service.markNotificationRead(id);
                    } catch (_) {}
                  }
                }
              }
              ref.invalidate(notificationsProvider);
              ref.invalidate(unreadNotificationCountProvider);
            },
          ),
        ],
      ),
      body: notificationsAsync.when(
        data: (notifications) {
          if (notifications.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.notifications_off_outlined, size: 64, color: AppTheme.border),
                  const SizedBox(height: 16),
                  Text(
                    'لا توجد إشعارات',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppTheme.textMuted),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(notificationsProvider);
              ref.invalidate(unreadNotificationCountProvider);
              return ref.refresh(notificationsProvider.future);
            },
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: notifications.length,
              itemBuilder: (context, index) {
                return _NotificationTile(notification: notifications[index]);
              },
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline_rounded, size: 48, color: AppTheme.error),
              const SizedBox(height: 16),
              Text(
                'تعذّر تحميل الإشعارات',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  final Map<String, dynamic> notification;

  const _NotificationTile({required this.notification});

  bool get _isRead => notification['is_read'] == true || notification['read_at'] != null;

  String get _title =>
      (notification['title_ar'] ?? notification['title'] ?? '').toString();

  String get _body =>
      (notification['body_ar'] ?? notification['body'] ?? '').toString();

  String? get _deepLink => notification['deep_link']?.toString();

  String? get _category => notification['category']?.toString();

  String _relativeTime(BuildContext context) {
    final createdAt = notification['created_at'];
    if (createdAt == null) return '';
    try {
      final dt = DateTime.parse(createdAt.toString());
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'الآن';
      if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} دقيقة';
      if (diff.inHours < 24) return 'منذ ${diff.inHours} ساعة';
      if (diff.inDays < 7) return 'منذ ${diff.inDays} يوم';
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  IconData _categoryIcon() {
    switch (_category) {
      case 'purchase':
        return Icons.shopping_cart_outlined;
      case 'deposit':
        return Icons.account_balance_wallet_outlined;
      case 'network':
        return Icons.wifi_rounded;
      case 'system':
        return Icons.settings_outlined;
      case 'offer':
        return Icons.local_offer_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: _isRead ? null : AppTheme.primarySoft,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _isRead
              ? AppTheme.border
              : AppTheme.primarySoft,
          child: Icon(
            _categoryIcon(),
            color: _isRead ? AppTheme.textMuted : AppTheme.primary,
            size: 20,
          ),
        ),
        title: Text(
          _title.isNotEmpty ? _title : 'إشعار',
          style: TextStyle(
            fontWeight: _isRead ? FontWeight.normal : FontWeight.bold,
            fontSize: 14,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_body.isNotEmpty)
              Text(
                _body,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 4),
            Text(
              _relativeTime(context),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textMuted,
                    fontSize: 11,
                  ),
            ),
          ],
        ),
        trailing: _isRead
            ? null
            : Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppTheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
        onTap: () async {
          // تأشير كمقروء
          if (!_isRead) {
            final id = (notification['inbox_id'] ?? notification['id'])?.toString();
            if (id != null) {
              try {
                await ref.read(supabaseServiceProvider).markNotificationRead(id);
                ref.invalidate(notificationsProvider);
                ref.invalidate(unreadNotificationCountProvider);
              } catch (_) {}
            }
          }

          // deep_link — best-effort navigation (no deep-link router yet)
          if (_deepLink != null && _deepLink!.isNotEmpty && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('$_title — تم التأشير كمقروء'),
                duration: const Duration(seconds: 1),
              ),
            );
          }
        },
      ),
    );
  }
}
