import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/entities.dart';
import 'admin_common_widgets.dart';
import 'admin_providers.dart';

class AdminAuditScreen extends ConsumerWidget {
  const AdminAuditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(adminAuditEventsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('سجل التدقيق'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.read(adminAuditEventsProvider.notifier).refresh(),
          ),
        ],
      ),
      body: eventsAsync.when(
        data: (events) => _AuditBody(
          events: events,
          onRefresh: () =>
              ref.read(adminAuditEventsProvider.notifier).refresh(),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AdminErrorState(
          message: 'حدث خطأ في تحميل السجل: $e',
          onRetry: () => ref.read(adminAuditEventsProvider.notifier).refresh(),
        ),
      ),
    );
  }
}

class _AuditBody extends StatelessWidget {
  final List<AdminAuditEvent> events;
  final Future<void> Function() onRefresh;

  const _AuditBody({required this.events, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: events.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 120),
                AdminEmptyState(
                  title: 'لا توجد أحداث',
                  subtitle: 'سجل التدقيق فارغ حالياً',
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: events.length,
              itemBuilder: (_, i) => _AuditEventCard(event: events[i]),
            ),
    );
  }
}

class _AuditEventCard extends StatelessWidget {
  final AdminAuditEvent event;

  const _AuditEventCard({required this.event});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _actionLabel(event.action),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                AdminStatusChip(
                  label: _resultLabel(event.result),
                  color: _resultColor(event.result),
                ),
              ],
            ),
            const SizedBox(height: 8),
            AdminInfoRow(
              label: 'الكيان',
              value:
                  '${event.entityType}${event.entityId != null ? ' (${event.entityId})' : ''}',
            ),
            AdminInfoRow(label: 'الدور', value: event.actorRole),
            AdminInfoRow(
              label: 'التاريخ',
              value: _formatDateTime(event.occurredAt),
            ),
            if (event.reasonCode != null)
              AdminInfoRow(label: 'سبب', value: event.reasonCode),
          ],
        ),
      ),
    );
  }

  String _actionLabel(String action) {
    switch (action) {
      case 'ADMIN_APPROVE_NETWORK':
        return 'موافقة على شبكة';
      case 'ADMIN_SUSPEND_NETWORK':
        return 'تعليق شبكة';
      case 'ADMIN_VERIFY_SSID_ALIAS':
        return 'توثيق اسم لاسلكي';
      case 'ADMIN_REJECT_SSID_ALIAS':
        return 'رفض اسم لاسلكي';
      case 'RESOLVE_NETWORK_REQUEST':
        return 'معالجة طلب شبكة';
      default:
        return action;
    }
  }

  String _resultLabel(String result) {
    switch (result) {
      case 'success':
        return 'نجاح';
      case 'failure':
        return 'فشل';
      case 'denied':
        return 'مرفوض';
      default:
        return result;
    }
  }

  Color _resultColor(String result) {
    switch (result) {
      case 'success':
        return AppTheme.success;
      case 'failure':
        return AppTheme.error;
      case 'denied':
        return AppTheme.warning;
      default:
        return AppTheme.textSecondary;
    }
  }

  String _formatDateTime(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}
