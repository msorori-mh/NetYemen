import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/entities.dart';
import 'admin_common_widgets.dart';
import 'admin_providers.dart';
import 'admin_request_detail_screen.dart';

class AdminRequestsScreen extends ConsumerWidget {
  const AdminRequestsScreen({super.key});

  static const _filters = {
    'الكل': null,
    'قيد الإرسال': 'submitted',
    'قيد المراجعة': 'under_review',
    'مقبولة': 'approved',
    'مرفوضة': 'rejected',
    'مطابقة': 'matched_existing',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(adminRequestsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('طلبات الشبكات'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(adminRequestsProvider.notifier).refresh(),
          ),
        ],
      ),
      body: requestsAsync.when(
        data: (requests) => _RequestsBody(
          requests: requests,
          onRefresh: () => ref.read(adminRequestsProvider.notifier).refresh(),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AdminErrorState(
          message: 'حدث خطأ في تحميل الطلبات: $e',
          onRetry: () => ref.read(adminRequestsProvider.notifier).refresh(),
        ),
      ),
    );
  }
}

class _RequestsBody extends ConsumerStatefulWidget {
  final List<AdminNetworkRequest> requests;
  final Future<void> Function() onRefresh;

  const _RequestsBody({
    required this.requests,
    required this.onRefresh,
  });

  @override
  ConsumerState<_RequestsBody> createState() => _RequestsBodyState();
}

class _RequestsBodyState extends ConsumerState<_RequestsBody> {
  String _selectedFilter = 'الكل';

  List<AdminNetworkRequest> get _filteredRequests {
    final status = AdminRequestsScreen._filters[_selectedFilter];
    if (status == null) return widget.requests;
    return widget.requests.where((r) => r.status == status).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: AdminRequestsScreen._filters.keys.map((label) {
              final selected = label == _selectedFilter;
              return Padding(
                padding: const EdgeInsets.only(left: 8),
                child: ChoiceChip(
                  label: Text(label),
                  selected: selected,
                  onSelected: (_) {
                    setState(() => _selectedFilter = label);
                    final status = AdminRequestsScreen._filters[label];
                    ref.read(adminRequestsProvider.notifier).setStatusFilter(status);
                  },
                ),
              );
            }).toList(),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: widget.onRefresh,
            child: _filteredRequests.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 120),
                      AdminEmptyState(
                        title: 'لا توجد طلبات',
                        subtitle: 'لا توجد طلبات تطابق الفلتر المحدد',
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _filteredRequests.length,
                    itemBuilder: (_, i) => _RequestCard(
                      request: _filteredRequests[i],
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _RequestCard extends StatelessWidget {
  final AdminNetworkRequest request;

  const _RequestCard({required this.request});

  @override
  Widget build(BuildContext context) {
    return AdminListCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AdminRequestDetailScreen(requestId: request.id),
        ),
      ),
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
                      request.requesterName ?? 'مستخدم مجهول',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              AdminStatusChip(
                label: request.statusLabel,
                color: statusColor(request.status),
              ),
            ],
          ),
          if (request.proposedNetworkName != null &&
              request.proposedNetworkName!.isNotEmpty) ...[
            const SizedBox(height: 8),
            AdminInfoRow(
              label: 'الاسم المقترح',
              value: request.proposedNetworkName,
            ),
          ],
          if (request.matchedNetworkName != null) ...[
            const SizedBox(height: 4),
            AdminInfoRow(
              label: 'الشبكة المطابقة',
              value: request.matchedNetworkName,
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
        ],
      ),
    );
  }
}
