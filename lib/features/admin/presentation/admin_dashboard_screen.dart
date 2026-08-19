import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/entities.dart';
import 'admin_common_widgets.dart';
import 'admin_packages_screen.dart';
import 'admin_providers.dart';
import 'admin_requests_screen.dart';
import 'admin_networks_screen.dart';
import 'admin_users_screen.dart';
import 'admin_audit_screen.dart';
import '../../finance/presentation/payment_destinations_screen.dart';
import '../../finance/presentation/settlement_batches_screen.dart';
import '../../notifications/presentation/admin_notification_composer_screen.dart';
import '../../support/presentation/support_screens.dart';
import 'admin_card_vault_ingest_screen.dart';

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kpisAsync = ref.watch(adminDashboardKpiProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة الإدارة'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(adminDashboardKpiProvider),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(adminDashboardKpiProvider),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            kpisAsync.when(
              data: (kpis) => _KpiGrid(kpis: kpis),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => AdminErrorState(
                message: 'حدث خطأ في تحميل المؤشرات: $e',
                onRetry: () => ref.invalidate(adminDashboardKpiProvider),
              ),
            ),
            const SizedBox(height: 24),
            const _NavigationSection(),
          ],
        ),
      ),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  final AdminDashboardKpi kpis;

  const _KpiGrid({required this.kpis});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.3,
      children: [
        _KpiCard(
          label: 'الشبكات النشطة',
          value: kpis.activeNetworks,
          icon: Icons.wifi,
          color: AppTheme.success,
        ),
        _KpiCard(
          label: 'طلبات قيد المراجعة',
          value: kpis.pendingRequests,
          icon: Icons.pending_actions,
          color: AppTheme.warning,
        ),
        _KpiCard(
          label: 'طلبات مقبولة',
          value: kpis.approvedRequests,
          icon: Icons.check_circle_outline,
          color: AppTheme.info,
        ),
        _KpiCard(
          label: 'طلبات مرفوضة',
          value: kpis.rejectedRequests,
          icon: Icons.cancel_outlined,
          color: AppTheme.error,
        ),
        _KpiCard(
          label: 'الباقات النشطة',
          value: kpis.activePackages,
          icon: Icons.card_giftcard,
          color: AppTheme.primary,
        ),
        _KpiCard(
          label: 'باقات نافدة',
          value: kpis.outOfStockPackages,
          icon: Icons.inventory_2_outlined,
          color: AppTheme.error,
        ),
        _KpiCard(
          label: 'ملاك الشبكات',
          value: kpis.networkOwners,
          icon: Icons.people_outline,
          color: AppTheme.accent,
        ),
        _KpiCard(
          label: 'مشغّلو الشبكات',
          value: kpis.networkOperators,
          icon: Icons.engineering_outlined,
          color: AppTheme.accentDark,
        ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final Color color;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              value.toString(),
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavigationSection extends StatelessWidget {
  const _NavigationSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'الإدارة',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        _NavCard(
          icon: Icons.support_agent_outlined,
          title: 'الإشراف على الدعم والنزاعات',
          subtitle: 'متابعة جميع الحالات ومؤشرات SLA',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const SupportQueueScreen(
                includeClosed: true,
                title: 'الإشراف على الدعم',
              ),
            ),
          ),
        ),
        _NavCard(
          icon: Icons.list_alt_outlined,
          title: 'طلبات الشبكات',
          subtitle: 'مراجعة ومعالجة الطلبات',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AdminRequestsScreen()),
          ),
        ),
        _NavCard(
          icon: Icons.wifi_outlined,
          title: 'الشبكات',
          subtitle: 'الموافقة والتعليق والتوثيق',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AdminNetworksScreen()),
          ),
        ),
        _NavCard(
          icon: Icons.card_giftcard_outlined,
          title: 'الباقات والمخزون',
          subtitle: 'مراقبة الباقات والمخزون',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AdminPackagesScreen()),
          ),
        ),
        _NavCard(
          icon: Icons.people_outline,
          title: 'المستخدمين',
          subtitle: 'الأدوار والعضويات',
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const AdminUsersScreen())),
        ),
        _NavCard(
          icon: Icons.history_outlined,
          title: 'سجل التدقيق',
          subtitle: 'الأحداث والعمليات الإدارية',
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const AdminAuditScreen())),
        ),
        _NavCard(
          icon: Icons.campaign_outlined,
          title: 'مؤلف الإعلانات',
          subtitle: 'إعلانات وتحديثات المنصة',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const AdminNotificationComposerScreen(),
            ),
          ),
        ),
        _NavCard(
          icon: Icons.account_balance_outlined,
          title: 'وجهات الدفع',
          subtitle: 'إدارة قنوات الإيداع والدفع',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const PaymentDestinationsScreen(),
            ),
          ),
        ),
        _NavCard(
          icon: Icons.calculate_outlined,
          title: 'دفعات التسوية',
          subtitle: 'إنشاء واعتماد وتسجيل دفعات التسوية',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SettlementBatchesScreen()),
          ),
        ),
        _NavCard(
          icon: Icons.vpn_key_outlined,
          title: 'استيراد كروت مشفرة',
          subtitle: 'إدخال دفعات كروت إلى الخزنة',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const AdminCardVaultIngestScreen(),
            ),
          ),
        ),
      ],
    );
  }
}

class _NavCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _NavCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon, color: AppTheme.primary),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_left),
        onTap: onTap,
      ),
    );
  }
}
