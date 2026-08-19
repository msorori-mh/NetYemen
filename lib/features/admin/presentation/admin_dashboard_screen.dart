import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/entities.dart';
import 'admin_access.dart';
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

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminAccessGate(child: _AdminDashboardContent());
  }
}

class _AdminDashboardContent extends ConsumerWidget {
  const _AdminDashboardContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capabilities = ref.watch(adminCapabilitiesProvider);
    final canViewOverview = capabilities.contains(
      AdminCapability.overview,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة إدارة واصل نت'),
        actions: [
          if (canViewOverview)
            IconButton(
              tooltip: 'تحديث المؤشرات',
              icon: const Icon(Icons.refresh),
              onPressed: () => ref.invalidate(adminDashboardKpiProvider),
            ),
        ],
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: RefreshIndicator(
          onRefresh: () async {
            if (canViewOverview) {
              ref.invalidate(adminDashboardKpiProvider);
            }
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _ConsoleHeader(capabilities: capabilities),
              const SizedBox(height: 20),
              if (canViewOverview) const _KpiSection(),
              if (canViewOverview) const SizedBox(height: 24),
              _NavigationSection(capabilities: capabilities),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConsoleHeader extends StatelessWidget {
  final Set<AdminCapability> capabilities;

  const _ConsoleHeader({required this.capabilities});

  @override
  Widget build(BuildContext context) {
    final isFinanceOnly = capabilities.contains(AdminCapability.payments) &&
        !capabilities.contains(AdminCapability.overview);

    return Card(
      color: AppTheme.primary.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
              child: Icon(
                isFinanceOnly
                    ? Icons.account_balance_wallet_outlined
                    : Icons.admin_panel_settings_outlined,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isFinanceOnly
                        ? 'مساحة العمليات المالية'
                        : 'مركز العمليات الإدارية',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'تظهر الوحدات وفق صلاحيات الحساب، وتبقى صلاحيات الخادم هي المرجع النهائي.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KpiSection extends ConsumerWidget {
  const _KpiSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kpisAsync = ref.watch(adminDashboardKpiProvider);
    return kpisAsync.when(
      data: (kpis) => _KpiGrid(kpis: kpis),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => AdminErrorState(
        message: 'تعذر تحميل المؤشرات الإدارية.',
        onRetry: () => ref.invalidate(adminDashboardKpiProvider),
      ),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  final AdminDashboardKpi kpis;

  const _KpiGrid({required this.kpis});

  @override
  Widget build(BuildContext context) {
    final cards = [
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
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1100
            ? 4
            : constraints.maxWidth >= 700
                ? 3
                : 2;
        const spacing = 12.0;
        final width =
            (constraints.maxWidth - (columns - 1) * spacing) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final card in cards)
              SizedBox(width: width, height: 112, child: card),
          ],
        );
      },
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
  final Set<AdminCapability> capabilities;

  const _NavigationSection({required this.capabilities});

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      if (capabilities.contains(AdminCapability.support))
        _NavCard(
          icon: Icons.support_agent_outlined,
          title: 'الدعم والنزاعات',
          subtitle: 'متابعة الحالات ومؤشرات SLA',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const SupportQueueScreen(
                includeClosed: true,
                title: 'الإشراف على الدعم',
              ),
            ),
          ),
        ),
      if (capabilities.contains(AdminCapability.networkRequests))
        _NavCard(
          icon: Icons.list_alt_outlined,
          title: 'طلبات الشبكات',
          subtitle: 'مراجعة ومعالجة الطلبات',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AdminRequestsScreen()),
          ),
        ),
      if (capabilities.contains(AdminCapability.networks))
        _NavCard(
          icon: Icons.wifi_outlined,
          title: 'الشبكات',
          subtitle: 'الموافقة والتعليق وتوثيق SSID',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AdminNetworksScreen()),
          ),
        ),
      if (capabilities.contains(AdminCapability.packages))
        _NavCard(
          icon: Icons.inventory_2_outlined,
          title: 'الباقات والمخزون',
          subtitle: 'متابعة الباقات والأرصدة',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AdminPackagesScreen()),
          ),
        ),
      if (capabilities.contains(AdminCapability.users))
        _NavCard(
          icon: Icons.people_outline,
          title: 'المستخدمون والعضويات',
          subtitle: 'الأدوار وعضويات الشبكات',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AdminUsersScreen()),
          ),
        ),
      if (capabilities.contains(AdminCapability.audit))
        _NavCard(
          icon: Icons.history_outlined,
          title: 'سجل التدقيق',
          subtitle: 'الأحداث والعمليات الإدارية',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AdminAuditScreen()),
          ),
        ),
      if (capabilities.contains(AdminCapability.notifications))
        _NavCard(
          icon: Icons.campaign_outlined,
          title: 'الإعلانات والإشعارات',
          subtitle: 'إنشاء الإعلانات ومراجعة التسليم',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const AdminNotificationComposerScreen(),
            ),
          ),
        ),
      if (capabilities.contains(AdminCapability.payments))
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
      if (capabilities.contains(AdminCapability.settlements))
        _NavCard(
          icon: Icons.calculate_outlined,
          title: 'دفعات التسوية',
          subtitle: 'الإنشاء والاعتماد وتسجيل الدفع',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SettlementBatchesScreen()),
          ),
        ),
      if (capabilities.contains(AdminCapability.cardVault))
        _NavCard(
          icon: Icons.vpn_key_outlined,
          title: 'خزنة الكروت',
          subtitle: 'استيراد دفعات مشفرة دون عرض الأسرار',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const AdminCardVaultIngestScreen(),
            ),
          ),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'الوحدات المتاحة',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1050
                ? 3
                : constraints.maxWidth >= 650
                    ? 2
                    : 1;
            const spacing = 12.0;
            final width =
                (constraints.maxWidth - (columns - 1) * spacing) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final card in cards) SizedBox(width: width, child: card),
              ],
            );
          },
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
      margin: EdgeInsets.zero,
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
