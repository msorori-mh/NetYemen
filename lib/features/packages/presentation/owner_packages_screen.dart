import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/entities.dart';
import 'inventory_adjustment_screen.dart';
import 'package_form_screen.dart';
import 'package_providers.dart';

class OwnerPackagesScreen extends ConsumerWidget {
  final String networkId;
  final String networkName;

  const OwnerPackagesScreen({
    super.key,
    required this.networkId,
    required this.networkName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packagesAsync = ref.watch(networkPackagesProvider(networkId));

    return Scaffold(
      appBar: AppBar(title: Text('باقات $networkName')),
      body: packagesAsync.when(
        data: (packages) => _buildContent(context, ref, packages),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorState(message: error.toString()),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _navigateToCreate(context),
        icon: const Icon(Icons.add),
        label: const Text('باقة جديدة'),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    List<NetworkPackage> packages,
  ) {
    if (packages.isEmpty) {
      return const _EmptyState();
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: packages.length,
      itemBuilder: (context, index) {
        final package = packages[index];
        return _OwnerPackageCard(package: package, networkId: networkId);
      },
    );
  }

  void _navigateToCreate(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PackageFormScreen(networkId: networkId),
      ),
    );
  }
}

class _OwnerPackageCard extends ConsumerWidget {
  final NetworkPackage package;
  final String networkId;

  const _OwnerPackageCard({required this.package, required this.networkId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balanceAsync = ref.watch(packageBalanceProvider(package.id));

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        title: Text(package.name),
        subtitle: Text(
          '${package.displayPrice} • ${_statusLabel(package.status)}',
          style: TextStyle(
            color: _statusColor(package.status),
            fontWeight: FontWeight.w600,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (package.description != null &&
                    package.description!.isNotEmpty)
                  Text(
                    package.description!,
                    style: const TextStyle(color: AppTheme.textSecondary),
                  ),
                const SizedBox(height: 12),
                _InfoRow(
                  label: 'المدة',
                  value: package.durationText.isEmpty
                      ? '—'
                      : package.durationText,
                ),
                _InfoRow(
                  label: 'السرعة',
                  value: package.speedMbps != null
                      ? '${package.speedMbps} Mbps'
                      : '—',
                ),
                _InfoRow(
                  label: 'النوع',
                  value: _packageTypeLabel(package.packageType),
                ),
                _InfoRow(
                  label: 'المخزون المتاح',
                  value: balanceAsync.when(
                    data: (b) => b == null
                        ? '—'
                        : '${b.availableUnits} / ${b.totalUnits}',
                    loading: () => '...',
                    error: (_, __) => 'خطأ',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (package.status != 'archived') ...[
                      _ActionButton(
                        label: 'تعديل',
                        icon: Icons.edit,
                        onPressed: () => _navigateToEdit(context),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (package.status == 'draft' ||
                        package.status == 'inactive')
                      _ActionButton(
                        label: 'نشر',
                        icon: Icons.publish,
                        onPressed: () => _publish(context, ref),
                      )
                    else if (package.status == 'active') ...[
                      _ActionButton(
                        label: 'إخفاء',
                        icon: Icons.unpublished,
                        onPressed: () => _deactivate(context, ref),
                      ),
                    ],
                    const SizedBox(width: 8),
                    _ActionButton(
                      label: 'المخزون',
                      icon: Icons.inventory,
                      onPressed: () => _adjustInventory(context),
                    ),
                    const Spacer(),
                    if (package.status != 'archived')
                      IconButton(
                        icon: const Icon(
                          Icons.archive,
                          color: AppTheme.textSecondary,
                        ),
                        onPressed: () => _archive(context, ref),
                        tooltip: 'أرشفة',
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToEdit(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            PackageFormScreen(networkId: networkId, package: package),
      ),
    );
  }

  void _adjustInventory(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InventoryAdjustmentScreen(package: package),
      ),
    );
  }

  Future<void> _publish(BuildContext context, WidgetRef ref) async {
    await _runAction(
      context,
      ref,
      () => ref.read(packageNotifierProvider(package.id).notifier).publish(),
      'تم نشر الباقة',
    );
  }

  Future<void> _deactivate(BuildContext context, WidgetRef ref) async {
    await _runAction(
      context,
      ref,
      () => ref.read(packageNotifierProvider(package.id).notifier).deactivate(),
      'تم إخفاء الباقة',
    );
  }

  Future<void> _archive(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الأرشفة'),
        content: const Text('لا يمكن التراجع عن أرشفة الباقة. متابعة؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('أرشفة', style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    await _runAction(
      context,
      ref,
      () => ref.read(packageNotifierProvider(package.id).notifier).archive(),
      'تم أرشفة الباقة',
    );
  }

  Future<void> _runAction(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() action,
    String successMessage,
  ) async {
    try {
      await action();
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(successMessage)));
      }
      ref.invalidate(networkPackagesProvider(networkId));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('خطأ: $e')));
      }
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'draft':
        return 'مسودة';
      case 'active':
        return 'منشورة';
      case 'inactive':
        return 'مخفية';
      case 'archived':
        return 'مؤرشفة';
      default:
        return status;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'active':
        return AppTheme.accent;
      case 'inactive':
      case 'draft':
        return AppTheme.warning;
      case 'archived':
        return AppTheme.textSecondary;
      default:
        return AppTheme.textSecondary;
    }
  }

  String _packageTypeLabel(String type) {
    switch (type) {
      case 'time':
        return 'زمنية';
      case 'volume':
        return 'حجمية';
      case 'unlimited':
        return 'غير محدود';
      default:
        return type;
    }
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: AppTheme.primary,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 64,
            color: AppTheme.textSecondary,
          ),
          SizedBox(height: 16),
          Text(
            'لا توجد باقات لهذه الشبكة',
            style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
          ),
          SizedBox(height: 8),
          Text(
            'اضغط على "باقة جديدة" لإنشاء أول باقة',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;

  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: AppTheme.error),
          const SizedBox(height: 16),
          Text('تعذر تحميل الباقات: $message', textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
