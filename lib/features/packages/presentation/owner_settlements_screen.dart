// lib/features/packages/presentation/owner_settlements_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../finance/presentation/finance_providers.dart';
import '../../finance/presentation/settlement_detail_screen.dart';

class OwnerSettlementsScreen extends ConsumerWidget {
  final String? networkId;

  const OwnerSettlementsScreen({super.key, this.networkId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settlementsAsync = ref.watch(ownerSettlementsProvider(networkId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('تسوياتي'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.invalidate(ownerSettlementsProvider(networkId)),
          ),
        ],
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: settlementsAsync.when(
          data: (settlements) =>
              _SettlementList(settlements: settlements, networkId: networkId),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('خطأ: $e')),
        ),
      ),
    );
  }
}

class _SettlementList extends StatelessWidget {
  final List<Map<String, dynamic>> settlements;
  final String? networkId;

  const _SettlementList({required this.settlements, this.networkId});

  @override
  Widget build(BuildContext context) {
    if (settlements.isEmpty) {
      return const Center(child: Text('لا توجد تسويات حالياً'));
    }

    final totals = _computeTotals(settlements);

    return Column(
      children: [
        _SummaryBanner(totals: totals),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: settlements.length,
            itemBuilder: (context, index) {
              final batch = settlements[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  title: Text(
                    '${batch['period_start']} إلى ${batch['period_end']}',
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('المبيعات: ${batch['gross_sales']}'),
                      Text('العمولة: ${batch['total_commission']}'),
                      Text('الصافي: ${batch['net_settlement']}'),
                    ],
                  ),
                  trailing: _StatusChip(
                    status: batch['status'] as String? ?? 'draft',
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SettlementDetailScreen(batch: batch),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Map<String, int> _computeTotals(List<Map<String, dynamic>> items) {
    var gross = 0;
    var commission = 0;
    var net = 0;
    for (final item in items) {
      gross += (item['gross_sales'] as num?)?.toInt() ?? 0;
      commission += (item['total_commission'] as num?)?.toInt() ?? 0;
      net += (item['net_settlement'] as num?)?.toInt() ?? 0;
    }
    return {'gross': gross, 'commission': commission, 'net': net};
  }
}

class _SummaryBanner extends StatelessWidget {
  final Map<String, int> totals;

  const _SummaryBanner({required this.totals});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.primary.withValues(alpha: 0.08),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          _summaryColumn(
            'إجمالي المبيعات',
            totals['gross'] ?? 0,
            AppTheme.success,
          ),
          _summaryColumn(
            'إجمالي العمولة',
            totals['commission'] ?? 0,
            AppTheme.error,
          ),
          _summaryColumn('الصافي', totals['net'] ?? 0, AppTheme.info),
        ],
      ),
    );
  }

  Widget _summaryColumn(String label, int value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            '$value',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'paid' => AppTheme.success,
      'approved' => AppTheme.info,
      'draft' => AppTheme.textSecondary,
      'ready_for_review' => AppTheme.warning,
      'cancelled' => AppTheme.error,
      'corrected' => AppTheme.primary,
      _ => AppTheme.textSecondary,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _statusLabel(status),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _statusLabel(String status) {
    return switch (status) {
      'paid' => 'مدفوع',
      'approved' => 'معتمد',
      'draft' => 'مسودة',
      'ready_for_review' => 'جاهز للمراجعة',
      'cancelled' => 'ملغي',
      'corrected' => 'مصحح',
      _ => status,
    };
  }
}
