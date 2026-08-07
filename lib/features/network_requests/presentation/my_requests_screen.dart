import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../network_requests/domain/entities.dart';
import '../../network_requests/presentation/network_request_providers.dart';

class MyRequestsScreen extends ConsumerWidget {
  const MyRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(myRequestsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('طلباتي'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(myRequestsProvider.notifier).refresh(),
          ),
        ],
      ),
      body: requestsAsync.when(
        data: (requests) {
          if (requests.isEmpty) {
            return const _EmptyRequestsState();
          }
          return RefreshIndicator(
            onRefresh: () => ref.read(myRequestsProvider.notifier).refresh(),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: requests.length,
              itemBuilder: (_, i) => _RequestCard(
                request: requests[i],
                onCancel: () => _cancelRequest(ref, requests[i].id),
              ),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppTheme.error),
              const SizedBox(height: 12),
              const Text('حدث خطأ في تحميل الطلبات'),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () =>
                    ref.read(myRequestsProvider.notifier).refresh(),
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _cancelRequest(WidgetRef ref, String requestId) async {
    try {
      final repo = ref.read(networkRequestRepositoryProvider);
      await repo.cancelRequest(requestId);
      ref.read(myRequestsProvider.notifier).refresh();
    } catch (_) {}
  }
}

class _RequestCard extends StatelessWidget {
  final NetworkAdditionRequest request;
  final VoidCallback onCancel;

  const _RequestCard({required this.request, required this.onCancel});

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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request.observedSsidDisplay,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatDate(request.createdAt),
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusChip(status: request.status),
              ],
            ),
            if (request.proposedNetworkName != null &&
                request.proposedNetworkName!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'الاسم المقترح: ${request.proposedNetworkName}',
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13),
              ),
            ],
            if (request.resolutionNote != null &&
                request.resolutionNote!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'ملاحظة: ${request.resolutionNote}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
            if (request.status == 'submitted') ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onCancel,
                  icon: const Icon(Icons.cancel_outlined,
                      size: 16, color: AppTheme.error),
                  label: const Text('إلغاء الطلب',
                      style: TextStyle(color: AppTheme.error, fontSize: 13)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;

    switch (status) {
      case 'submitted':
        color = AppTheme.info;
        label = 'قيد الإرسال';
        break;
      case 'under_review':
        color = AppTheme.warning;
        label = 'قيد المراجعة';
        break;
      case 'matched_existing':
        color = AppTheme.info;
        label = 'تمت مطابقته';
        break;
      case 'approved':
        color = AppTheme.success;
        label = 'تمت الموافقة';
        break;
      case 'rejected':
        color = AppTheme.error;
        label = 'مرفوض';
        break;
      case 'cancelled':
        color = AppTheme.textMuted;
        label = 'ملغي';
        break;
      default:
        color = AppTheme.textSecondary;
        label = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _EmptyRequestsState extends StatelessWidget {
  const _EmptyRequestsState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_outlined, size: 64, color: AppTheme.textMuted),
          SizedBox(height: 16),
          Text('لا توجد طلبات'),
          SizedBox(height: 8),
          Text(
            'لم تقم بإرسال أي طلب إضافة شبكة بعد',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
