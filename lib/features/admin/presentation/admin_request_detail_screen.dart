import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/app_providers.dart';
import '../domain/entities.dart';
import 'admin_common_widgets.dart';
import 'admin_providers.dart';

class AdminRequestDetailScreen extends ConsumerWidget {
  final String requestId;

  const AdminRequestDetailScreen({super.key, required this.requestId});

  static const _resolverRoles = {'platform_admin', 'support_agent'};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestAsync = ref.watch(adminRequestDetailProvider(requestId));
    final rolesAsync = ref.watch(currentUserRolesProvider);

    final canResolve = rolesAsync.when(
      data: (roles) => roles.any(_resolverRoles.contains),
      loading: () => false,
      error: (_, __) => false,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('تفاصيل الطلب'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.invalidate(adminRequestDetailProvider(requestId)),
          ),
        ],
      ),
      body: requestAsync.when(
        data: (request) =>
            _RequestDetailBody(request: request, canResolve: canResolve),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AdminErrorState(
          message: 'حدث خطأ في تحميل تفاصيل الطلب: $e',
          onRetry: () => ref.invalidate(adminRequestDetailProvider(requestId)),
        ),
      ),
    );
  }
}

class _RequestDetailBody extends ConsumerWidget {
  final AdminNetworkRequest request;
  final bool canResolve;

  const _RequestDetailBody({required this.request, required this.canResolve});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () async =>
          ref.invalidate(adminRequestDetailProvider(request.id)),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StatusHeader(request: request),
          const SizedBox(height: 16),
          _InfoCard(request: request),
          if (request.matchedNetworkName != null) ...[
            const SizedBox(height: 16),
            _MatchedNetworkCard(request: request),
          ],
          if (canResolve && !request.isTerminal) ...[
            const SizedBox(height: 24),
            _ActionButtons(request: request),
          ],
          if (!canResolve) ...[
            const SizedBox(height: 16),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.lock_outline, color: AppTheme.textSecondary),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'لا تملك صلاحية معالجة هذا الطلب.',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusHeader extends StatelessWidget {
  final AdminNetworkRequest request;

  const _StatusHeader({required this.request});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    request.observedSsidDisplay,
                    style: const TextStyle(
                      fontSize: 18,
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
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final AdminNetworkRequest request;

  const _InfoCard({required this.request});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'معلومات الطلب',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            AdminInfoRow(
              label: 'الاسم المقترح',
              value: request.proposedNetworkName,
            ),
            AdminInfoRow(label: 'المحافظة', value: request.governorate),
            AdminInfoRow(label: 'المدينة', value: request.city),
            AdminInfoRow(label: 'الحي', value: request.district),
            AdminInfoRow(label: 'ملاحظات', value: request.notes),
            AdminInfoRow(
              label: 'تاريخ الإرسال',
              value: _formatDate(request.createdAt),
            ),
            if (request.resolvedAt != null)
              AdminInfoRow(
                label: 'تاريخ المعالجة',
                value: _formatDate(request.resolvedAt!),
              ),
            if (request.resolutionNote != null &&
                request.resolutionNote!.isNotEmpty)
              AdminInfoRow(
                label: 'ملاحظة المعالجة',
                value: request.resolutionNote,
              ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

class _MatchedNetworkCard extends StatelessWidget {
  final AdminNetworkRequest request;

  const _MatchedNetworkCard({required this.request});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'الشبكة المطابقة',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            AdminInfoRow(
              label: 'الاسم التجاري',
              value: request.matchedNetworkName,
            ),
            AdminInfoRow(
              label: 'الحالة',
              value: request.matchedNetworkStatus != null
                  ? _networkStatusLabel(request.matchedNetworkStatus!)
                  : null,
            ),
            AdminInfoRow(
              label: 'التوثيق',
              value: request.matchedNetworkVerificationStatus != null
                  ? _verificationLabel(
                      request.matchedNetworkVerificationStatus!,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  String _networkStatusLabel(String status) {
    switch (status) {
      case 'pending_approval':
        return 'في انتظار الموافقة';
      case 'active':
        return 'نشطة';
      case 'suspended':
        return 'معلّقة';
      case 'rejected':
        return 'مرفوضة';
      default:
        return status;
    }
  }

  String _verificationLabel(String status) {
    switch (status) {
      case 'unverified':
        return 'غير موثّقة';
      case 'verified':
        return 'موثّقة';
      case 'rejected':
        return 'مرفوضة';
      default:
        return status;
    }
  }
}

class _ActionButtons extends ConsumerWidget {
  final AdminNetworkRequest request;

  const _ActionButtons({required this.request});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'إجراءات',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        if (request.status == 'submitted')
          ElevatedButton.icon(
            onPressed: () => _resolve(context, ref, 'under_review'),
            icon: const Icon(Icons.hourglass_top),
            label: const Text('قيد المراجعة'),
          ),
        if (request.status != 'matched_existing') ...[
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: () => _resolve(context, ref, 'approved'),
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('الموافقة'),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
          ),
        ],
        const SizedBox(height: 8),
        ElevatedButton.icon(
          onPressed: () => _resolve(context, ref, 'rejected'),
          icon: const Icon(Icons.cancel_outlined),
          label: const Text('الرفض'),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          onPressed: () => _matchExisting(context, ref),
          icon: const Icon(Icons.merge_type),
          label: const Text('مطابق مع شبكة موجودة'),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.info),
        ),
      ],
    );
  }

  Future<void> _resolve(
    BuildContext context,
    WidgetRef ref,
    String newStatus,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الإجراء'),
        content: Text(
          'هل تريد تغيير حالة الطلب إلى "${_statusLabel(newStatus)}"؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      await ref
          .read(adminRequestDetailProvider(request.id).notifier)
          .resolve(newStatus);
      if (context.mounted) {
        ref.invalidate(adminRequestsProvider);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم تحديث حالة الطلب')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('فشل تحديث الطلب: $e')));
      }
    }
  }

  Future<void> _matchExisting(BuildContext context, WidgetRef ref) async {
    final networksAsync = ref.read(adminNetworksProvider);
    final networks = networksAsync.valueOrNull ?? [];

    final selectedNetworkId = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('اختيار شبكة موجودة'),
        content: SizedBox(
          width: double.maxFinite,
          child: networks.isEmpty
              ? const Text('لا توجد شبكات متاحة')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: networks.length,
                  itemBuilder: (_, i) {
                    final network = networks[i];
                    return ListTile(
                      title: Text(network.commercialName),
                      subtitle: Text(
                        '${network.statusLabel} - ${network.verificationStatusLabel}',
                      ),
                      onTap: () => Navigator.of(context).pop(network.id),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );

    if (selectedNetworkId == null || !context.mounted) return;

    try {
      await ref
          .read(adminRequestDetailProvider(request.id).notifier)
          .resolve('matched_existing', matchedNetworkId: selectedNetworkId);
      if (context.mounted) {
        ref.invalidate(adminRequestsProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تمت مطابقة الطلب مع شبكة موجودة')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('فشلت المطابقة: $e')));
      }
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'under_review':
        return 'قيد المراجعة';
      case 'approved':
        return 'مقبول';
      case 'rejected':
        return 'مرفوض';
      default:
        return status;
    }
  }
}
