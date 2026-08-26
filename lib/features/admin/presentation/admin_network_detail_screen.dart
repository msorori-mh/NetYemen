import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/app_providers.dart';
import '../domain/entities.dart';
import 'admin_common_widgets.dart';
import 'admin_providers.dart';

class AdminNetworkDetailScreen extends ConsumerWidget {
  final String networkId;

  const AdminNetworkDetailScreen({super.key, required this.networkId});

  static const _adminRoles = {'platform_admin'};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final networkAsync = ref.watch(adminNetworkDetailProvider(networkId));
    final aliasesAsync = ref.watch(adminNetworkAliasesProvider(networkId));
    final rolesAsync = ref.watch(currentUserRolesProvider);

    final isAdmin = rolesAsync.when(
      data: (roles) => roles.any(_adminRoles.contains),
      loading: () => false,
      error: (_, __) => false,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('تفاصيل الشبكة'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(adminNetworkDetailProvider(networkId));
              ref.invalidate(adminNetworkAliasesProvider(networkId));
            },
          ),
        ],
      ),
      body: networkAsync.when(
        data: (network) => _NetworkDetailBody(
          network: network,
          aliasesAsync: aliasesAsync,
          isAdmin: isAdmin,
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AdminErrorState(
          message: 'تعذر تحميل تفاصيل الشبكة. حاول مرة أخرى.',
          onRetry: () => ref.invalidate(adminNetworkDetailProvider(networkId)),
        ),
      ),
    );
  }
}

class _NetworkDetailBody extends ConsumerWidget {
  final AdminNetwork network;
  final AsyncValue<List<AdminSsidAlias>> aliasesAsync;
  final bool isAdmin;

  const _NetworkDetailBody({
    required this.network,
    required this.aliasesAsync,
    required this.isAdmin,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(adminNetworkDetailProvider(network.id));
        ref.invalidate(adminNetworkAliasesProvider(network.id));
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _NetworkHeader(network: network),
          const SizedBox(height: 16),
          _NetworkInfoCard(network: network),
          if (isAdmin && network.isAdminActionable) ...[
            const SizedBox(height: 24),
            _NetworkActions(network: network),
          ],
          const SizedBox(height: 24),
          const AdminSectionTitle(title: 'أسماء الشبكة اللاسلكية'),
          aliasesAsync.when(
            data: (aliases) => _AliasesList(
              networkId: network.id,
              aliases: aliases,
              isAdmin: isAdmin,
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => AdminErrorState(
              message: 'تعذر تحميل أسماء الشبكة اللاسلكية. حاول مرة أخرى.',
              onRetry: () =>
                  ref.invalidate(adminNetworkAliasesProvider(network.id)),
            ),
          ),
        ],
      ),
    );
  }
}

class _NetworkHeader extends StatelessWidget {
  final AdminNetwork network;

  const _NetworkHeader({required this.network});

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
                    network.commercialName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (network.locationText.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      network.locationText,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Column(
              children: [
                AdminStatusChip(
                  label: network.statusLabel,
                  color: statusColor(network.status),
                ),
                const SizedBox(height: 8),
                AdminStatusChip(
                  label: network.verificationStatusLabel,
                  color: statusColor(network.verificationStatus),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NetworkInfoCard extends StatelessWidget {
  final AdminNetwork network;

  const _NetworkInfoCard({required this.network});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'معلومات الشبكة',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            AdminInfoRow(label: 'الوصف', value: network.description),
            AdminInfoRow(
              label: 'المالك',
              value: network.ownerNames.isEmpty
                  ? 'غير محدد'
                  : network.ownerNames.join(', '),
            ),
            AdminInfoRow(
              label: 'تاريخ الإنشاء',
              value: _formatDate(network.createdAt),
            ),
            if (network.approvedAt != null)
              AdminInfoRow(
                label: 'تاريخ الموافقة',
                value: _formatDate(network.approvedAt!),
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

class _NetworkActions extends ConsumerWidget {
  final AdminNetwork network;

  const _NetworkActions({required this.network});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'إجراءات إدارية',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        if (network.status == 'pending_approval')
          ElevatedButton.icon(
            onPressed: () => _approve(context, ref),
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('الموافقة على الشبكة'),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
          ),
        if (network.status != 'suspended') ...[
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: () => _suspend(context, ref),
            icon: const Icon(Icons.block),
            label: const Text('تعليق الشبكة'),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
          ),
        ] else ...[
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: () => _approve(context, ref),
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('إعادة تنشيط الشبكة'),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
          ),
        ],
      ],
    );
  }

  Future<void> _approve(BuildContext context, WidgetRef ref) async {
    final confirmed = await _confirmAction(
      context,
      title: 'الموافقة على الشبكة',
      message: 'هل تريد الموافقة على شبكة "${network.commercialName}"؟',
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(adminNetworkDetailProvider(network.id).notifier).approve();
      if (context.mounted) {
        ref.invalidate(adminNetworksProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تمت الموافقة على الشبكة')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(
            content: Text('تعذر تنفيذ الموافقة. حاول مرة أخرى.')));
      }
    }
  }

  Future<void> _suspend(BuildContext context, WidgetRef ref) async {
    final reason = await _showReasonDialog(
      context,
      title: 'تعليق الشبكة',
      label: 'سبب التعليق',
    );
    if (reason == null || !context.mounted) return;

    try {
      await ref
          .read(adminNetworkDetailProvider(network.id).notifier)
          .suspend(reason: reason);
      if (context.mounted) {
        ref.invalidate(adminNetworksProvider);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم تعليق الشبكة')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
            const SnackBar(content: Text('تعذر تعليق الشبكة. حاول مرة أخرى.')));
      }
    }
  }

  Future<bool?> _confirmAction(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
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
  }

  Future<String?> _showReasonDialog(
    BuildContext context, {
    required String title,
    required String label,
  }) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: label,
            alignLabelWithHint: true,
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    return result?.isNotEmpty == true ? result : null;
  }
}

class _AliasesList extends StatelessWidget {
  final String networkId;
  final List<AdminSsidAlias> aliases;
  final bool isAdmin;

  const _AliasesList({
    required this.networkId,
    required this.aliases,
    required this.isAdmin,
  });

  @override
  Widget build(BuildContext context) {
    if (aliases.isEmpty) {
      return const AdminEmptyState(
        title: 'لا توجد أسماء لاسلكية',
        subtitle: 'لم يتم تسجيل أي اسم لاسلكي لهذه الشبكة',
      );
    }

    return Column(
      children: aliases
          .map(
            (alias) => _AliasCard(
              networkId: networkId,
              alias: alias,
              isAdmin: isAdmin,
            ),
          )
          .toList(),
    );
  }
}

class _AliasCard extends ConsumerWidget {
  final String networkId;
  final AdminSsidAlias alias;
  final bool isAdmin;

  const _AliasCard({
    required this.networkId,
    required this.alias,
    required this.isAdmin,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                    alias.ssidDisplay,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                AdminStatusChip(
                  label: alias.statusLabel,
                  color: statusColor(alias.status),
                ),
              ],
            ),
            if (alias.ssidNormalized != null &&
                alias.ssidNormalized!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                alias.ssidNormalized!,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
            if (isAdmin && alias.isPending) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _verifyAlias(context, ref),
                      icon: const Icon(Icons.verified, size: 18),
                      label: const Text('توثيق'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.success,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _rejectAlias(context, ref),
                      icon: const Icon(Icons.cancel, size: 18),
                      label: const Text('رفض'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.error,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _verifyAlias(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(adminNetworkAliasesProvider(networkId).notifier)
          .verifyAlias(alias.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم توثيق الاسم اللاسلكي')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(
            content: Text('تعذر توثيق الاسم اللاسلكي. حاول مرة أخرى.')));
      }
    }
  }

  Future<void> _rejectAlias(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(adminNetworkAliasesProvider(networkId).notifier)
          .rejectAlias(alias.id);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم رفض الاسم اللاسلكي')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(
            content: Text('تعذر رفض الاسم اللاسلكي. حاول مرة أخرى.')));
      }
    }
  }
}
