import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/owned_network_model.dart';
import '../../providers/networks_providers.dart';
import '../../utils/app_theme.dart';
import 'package_form_screen.dart';

class NetworkDetailScreen extends ConsumerStatefulWidget {
  final OwnedNetwork network;

  const NetworkDetailScreen({super.key, required this.network});

  @override
  ConsumerState<NetworkDetailScreen> createState() => _NetworkDetailScreenState();
}

class _NetworkDetailScreenState extends ConsumerState<NetworkDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showAddSsidDialog(BuildContext context) {
    final displayController = TextEditingController();
    final normalizedController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('إضافة SSID للشبكة'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: displayController,
                decoration: const InputDecoration(labelText: 'اسم الشبكة (Display)'),
              ),
              TextField(
                controller: normalizedController,
                decoration: const InputDecoration(labelText: 'الاسم الموحد (Normalized)'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                final display = displayController.text.trim();
                final normalized = normalizedController.text.trim();
                if (display.isEmpty || normalized.isEmpty) return;
                
                try {
                  await ref.read(networksServiceProvider).createSsidAlias(
                    widget.network.id, display, normalized
                  );
                  if (context.mounted) {
                    Navigator.pop(context);
                    ref.invalidate(networkSsidAliasesProvider(widget.network.id));
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('خطأ: $e')),
                    );
                  }
                }
              },
              child: const Text('إضافة'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.network.commercialName),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primary,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textMuted,
          labelStyle: const TextStyle(fontWeight: FontWeight.w600),
          tabs: const [
            Tab(text: 'الباقات'),
            Tab(text: 'SSID Aliases'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Packages Tab
          _buildPackagesTab(),
          // SSID Aliases Tab
          _buildSsidTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (_tabController.index == 0) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PackageFormScreen(networkId: widget.network.id),
              ),
            ).then((_) {
              ref.invalidate(networkPackagesProvider(widget.network.id));
            });
          } else {
            _showAddSsidDialog(context);
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildPackagesTab() {
    final packagesAsync = ref.watch(networkPackagesProvider(widget.network.id));

    return packagesAsync.when(
      data: (packages) {
        if (packages.isEmpty) {
          return AppTheme.emptyState(
            icon: Icons.inventory_2_outlined,
            message: 'لا توجد باقات لهذه الشبكة.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: packages.length,
          itemBuilder: (context, index) {
            final pkg = packages[index];
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: AppTheme.cardShadow,
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pkg['name'],
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${pkg['price']} YER — ${pkg['package_type']}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (pkg['status'] == 'draft')
                      _actionIcon(
                        Icons.publish_rounded,
                        AppTheme.success,
                        'نشر',
                        () async {
                          try {
                            await ref.read(networksServiceProvider).publishNetworkPackage(pkg['id']);
                            ref.invalidate(networkPackagesProvider(widget.network.id));
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
                            }
                          }
                        },
                      ),
                    if (pkg['status'] == 'active')
                      _actionIcon(
                        Icons.block_rounded,
                        AppTheme.error,
                        'تعطيل',
                        () async {
                          try {
                            await ref.read(networksServiceProvider).deactivateNetworkPackage(pkg['id']);
                            ref.invalidate(networkPackagesProvider(widget.network.id));
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
                            }
                          }
                        },
                      ),
                    _actionIcon(
                      Icons.edit_rounded,
                      AppTheme.textSecondary,
                      'تعديل',
                      () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => PackageFormScreen(
                              networkId: widget.network.id,
                              packageData: pkg,
                            ),
                          ),
                        ).then((_) {
                          ref.invalidate(networkPackagesProvider(widget.network.id));
                        });
                      },
                    ),
                    if (pkg['status'] != null)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(start: 8),
                        child: AppTheme.statusChip(
                          pkg['status'] == 'active' ? 'نشطة' : (pkg['status'] == 'draft' ? 'مسودة' : pkg['status']),
                          color: pkg['status'] == 'active'
                              ? AppTheme.success.withValues(alpha: 0.12)
                              : AppTheme.warning.withValues(alpha: 0.12),
                          textColor: pkg['status'] == 'active' ? AppTheme.success : AppTheme.warning,
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
      loading: () => AppTheme.loadingIndicator(),
      error: (e, st) => AppTheme.errorState(
        message: 'تعذّر تحميل الباقات',
        onRetry: () => ref.invalidate(networkPackagesProvider(widget.network.id)),
      ),
    );
  }

  Widget _actionIcon(IconData icon, Color color, String tooltip, VoidCallback onTap) {
    return IconButton(
      icon: Icon(icon, color: color, size: 20),
      onPressed: onTap,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildSsidTab() {
    final ssidsAsync = ref.watch(networkSsidAliasesProvider(widget.network.id));

    return ssidsAsync.when(
      data: (ssids) {
        if (ssids.isEmpty) {
          return AppTheme.emptyState(
            icon: Icons.router_outlined,
            message: 'لا توجد SSID aliases لهذه الشبكة.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: ssids.length,
          itemBuilder: (context, index) {
            final ssid = ssids[index];
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: AppTheme.cardShadow,
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppTheme.primarySoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.wifi_rounded, color: AppTheme.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ssid['ssid_display'],
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Normalized: ${ssid['ssid_normalized']}',
                          style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ),
                  AppTheme.statusChip(
                    ssid['status'] == 'active' ? 'نشط' : ssid['status'],
                    color: ssid['status'] == 'active'
                        ? AppTheme.success.withValues(alpha: 0.12)
                        : AppTheme.textMuted.withValues(alpha: 0.12),
                    textColor: ssid['status'] == 'active' ? AppTheme.success : AppTheme.textMuted,
                  ),
                ],
              ),
            );
          },
        );
      },
      loading: () => AppTheme.loadingIndicator(),
      error: (e, st) => AppTheme.errorState(
        message: 'تعذّر تحميل SSIDs',
        onRetry: () => ref.invalidate(networkSsidAliasesProvider(widget.network.id)),
      ),
    );
  }
}
