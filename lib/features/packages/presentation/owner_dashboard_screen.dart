import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../finance/presentation/finance_providers.dart';
import 'owner_packages_screen.dart';
import 'owner_settlements_screen.dart';
import 'package_providers.dart';

class OwnerDashboardScreen extends ConsumerWidget {
  const OwnerDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ownedNetworksAsync = ref.watch(ownedNetworksProvider);
    final settlementsAsync = ref.watch(ownerSettlementsProvider(null));

    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة مالك الشبكة'),
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: ownedNetworksAsync.when(
          data: (networks) => _buildContent(context, ref, networks, settlementsAsync),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _ErrorState(message: error.toString()),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    List<dynamic> networks,
    AsyncValue<List<Map<String, dynamic>>> settlementsAsync,
  ) {
    if (networks.isEmpty) {
      return const _EmptyState();
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SettlementSummary(asyncValue: settlementsAsync),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const OwnerSettlementsScreen()),
          ),
          icon: const Icon(Icons.history),
          label: const Text('سجل التسويات'),
        ),
        const SizedBox(height: 16),
        const Text(
          'شبكاتي',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        ...networks.map((network) => Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                  child: Text(
                    network.commercialName.isNotEmpty
                        ? network.commercialName[0]
                        : '?',
                    style: const TextStyle(color: AppTheme.primary),
                  ),
                ),
                title: Text(network.commercialName),
                subtitle: Text(
                  network.locationText.isEmpty ? 'لا يوجد موقع' : network.locationText,
                ),
                trailing: const Icon(Icons.chevron_left),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => OwnerPackagesScreen(
                        networkId: network.id,
                        networkName: network.commercialName,
                      ),
                    ),
                  );
                },
              ),
            )),
      ],
    );
  }
}

class _SettlementSummary extends StatelessWidget {
  final AsyncValue<List<Map<String, dynamic>>> asyncValue;

  const _SettlementSummary({required this.asyncValue});

  @override
  Widget build(BuildContext context) {
    return asyncValue.when(
      data: (settlements) {
        var gross = 0;
        var commission = 0;
        var net = 0;
        for (final s in settlements) {
          gross += (s['gross_sales'] as num?)?.toInt() ?? 0;
          commission += (s['total_commission'] as num?)?.toInt() ?? 0;
          net += (s['net_settlement'] as num?)?.toInt() ?? 0;
        }
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ملخص التسويات',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _summaryItem('المبيعات', gross, AppTheme.success),
                    _summaryItem('العمولة', commission, AppTheme.error),
                    _summaryItem('الصافي', net, AppTheme.info),
                  ],
                ),
              ],
            ),
          ),
        );
      },
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (e, _) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('تعذر تحميل التسويات: $e'),
        ),
      ),
    );
  }

  Widget _summaryItem(String label, int value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            '$value',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
          ),
        ],
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
          Icon(Icons.business_outlined, size: 64, color: AppTheme.textSecondary),
          SizedBox(height: 16),
          Text(
            'لا تمتلك شبكات مسجلة حالياً',
            style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
          ),
          SizedBox(height: 8),
          Text(
            'يمكنك تسجيل شبكة جديدة عبر إدارة الشبكات',
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
          Text(
            'تعذر تحميل الشبكات: $message',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
