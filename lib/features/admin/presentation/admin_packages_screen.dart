import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/entities.dart';
import 'admin_common_widgets.dart';
import 'admin_providers.dart';

class AdminPackagesScreen extends ConsumerWidget {
  const AdminPackagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packagesAsync = ref.watch(adminPackagesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('الباقات والمخزون'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(adminPackagesProvider.notifier).refresh(),
          ),
        ],
      ),
      body: packagesAsync.when(
        data: (packages) => _PackagesBody(
          packages: packages,
          onRefresh: () => ref.read(adminPackagesProvider.notifier).refresh(),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AdminErrorState(
          message: 'حدث خطأ في تحميل الباقات: $e',
          onRetry: () => ref.read(adminPackagesProvider.notifier).refresh(),
        ),
      ),
    );
  }
}

class _PackagesBody extends StatelessWidget {
  final List<AdminPackageInventory> packages;
  final Future<void> Function() onRefresh;

  const _PackagesBody({
    required this.packages,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: packages.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 120),
                AdminEmptyState(
                  title: 'لا توجد باقات',
                  subtitle: 'لم يتم تسجيل أي باقات في النظام',
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: packages.length,
              itemBuilder: (_, i) => _PackageCard(package: packages[i]),
            ),
    );
  }
}

class _PackageCard extends StatelessWidget {
  final AdminPackageInventory package;

  const _PackageCard({required this.package});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: package.isOutOfStock
          ? AppTheme.error.withValues(alpha: 0.05)
          : null,
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
                        package.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        package.displayPrice,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                AdminStatusChip(
                  label: package.isOutOfStock ? 'غير متوفر' : 'متوفر',
                  color: package.isOutOfStock ? AppTheme.error : AppTheme.success,
                ),
              ],
            ),
            if (package.description != null &&
                package.description!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                package.description!,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetricChip(
                  label: 'المخزون الكلي',
                  value: package.totalUnits.toString(),
                ),
                _MetricChip(
                  label: 'المتوفر',
                  value: package.availableUnits.toString(),
                  color: package.isOutOfStock ? AppTheme.error : AppTheme.success,
                ),
                if (package.durationText.isNotEmpty)
                  _MetricChip(
                    label: 'المدة',
                    value: package.durationText,
                  ),
                if (package.speedMbps != null)
                  _MetricChip(
                    label: 'السرعة',
                    value: '${package.speedMbps} Mbps',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _MetricChip({
    required this.label,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontSize: 12,
          color: color ?? AppTheme.textSecondary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
