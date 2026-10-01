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
          message: 'تعذر تحميل الباقات والمخزون. أعد المحاولة.',
          onRetry: () => ref.read(adminPackagesProvider.notifier).refresh(),
        ),
      ),
    );
  }
}

class _PackagesBody extends StatefulWidget {
  final List<AdminPackageInventory> packages;
  final Future<void> Function() onRefresh;

  const _PackagesBody({required this.packages, required this.onRefresh});

  @override
  State<_PackagesBody> createState() => _PackagesBodyState();
}

class _PackagesBodyState extends State<_PackagesBody> {
  String _searchQuery = '';
  bool _outOfStockOnly = false;

  List<AdminPackageInventory> get _filteredPackages {
    return widget.packages.where((package) {
      if (_outOfStockOnly && !package.isOutOfStock) return false;
      if (_searchQuery.isEmpty) return true;

      final searchableText = [
        package.name,
        package.description,
        package.packageType,
        package.status,
        package.networkId,
      ].whereType<String>().join(' ').toLowerCase();

      return searchableText.contains(_searchQuery);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final packages = _filteredPackages;

    return Column(
      children: [
        AdminSearchField(
          hintText: 'ابحث باسم الباقة أو النوع أو معرف الشبكة',
          onChanged: (value) => setState(() => _searchQuery = value),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Align(
            alignment: Alignment.centerRight,
            child: FilterChip(
              label: const Text('النافد فقط'),
              selected: _outOfStockOnly,
              onSelected: (value) => setState(() => _outOfStockOnly = value),
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: widget.onRefresh,
            child: packages.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 120),
                      AdminEmptyState(
                        title: 'لا توجد باقات',
                        subtitle: 'لا توجد نتائج تطابق البحث أو الفلتر',
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: packages.length,
                    itemBuilder: (_, i) => _PackageCard(package: packages[i]),
                  ),
          ),
        ),
      ],
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
      color:
          package.isOutOfStock ? AppTheme.error.withValues(alpha: 0.05) : null,
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
                  color:
                      package.isOutOfStock ? AppTheme.error : AppTheme.success,
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
                  color:
                      package.isOutOfStock ? AppTheme.error : AppTheme.success,
                ),
                if (package.durationText.isNotEmpty)
                  _MetricChip(label: 'المدة', value: package.durationText),
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

  const _MetricChip({required this.label, required this.value, this.color});

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
