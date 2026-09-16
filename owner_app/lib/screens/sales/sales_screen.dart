// lib/screens/sales/sales_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/owner_providers.dart';
import '../../providers/sales_providers.dart';
import '../../utils/app_theme.dart';
import 'settlement_detail_screen.dart';

/// F-OWN-06: شاشة المبيعات — ملخّص تجاري + قائمة التسويات.
class SalesScreen extends ConsumerWidget {
  const SalesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final networksAsync = ref.watch(ownedNetworksProvider);
    final selectedNetwork = ref.watch(selectedSalesNetworkProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('المبيعات'),
      ),
      body: networksAsync.when(
        data: (networks) {
          if (networks.isEmpty) {
            return AppTheme.emptyState(
              icon: Icons.point_of_sale_outlined,
              message: 'لا توجد شبكات مسجَّلة باسمك.',
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(commercialSummaryProvider(selectedNetwork));
              ref.invalidate(settlementsProvider(selectedNetwork));
              return ref.refresh(ownedNetworksProvider.future);
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ───── فلتر الشبكة ─────
                DropdownButtonFormField<String?>(
                  initialValue: selectedNetwork,
                  decoration: const InputDecoration(
                    labelText: 'الشبكة',
                    prefixIcon: Icon(Icons.wifi_rounded),
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('كل الشبكات')),
                    ...networks.map((n) {
                      return DropdownMenuItem(value: n.id, child: Text(n.commercialName));
                    }),
                  ],
                  onChanged: (v) =>
                      ref.read(selectedSalesNetworkProvider.notifier).state = v,
                ),

                const SizedBox(height: 24),

                // ───── ملخّص تجاري ─────
                _CommercialSummarySection(networkId: selectedNetwork),

                const SizedBox(height: 24),

                // ───── عنوان التسويات ─────
                const Text(
                  'سجلّ التسويات',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 12),

                // ───── قائمة التسويات ─────
                _SettlementsList(networkId: selectedNetwork),
              ],
            ),
          );
        },
        loading: () => AppTheme.loadingIndicator(),
        error: (_, __) => AppTheme.errorState(
          message: 'تعذّر تحميل الشبكات.',
          onRetry: () => ref.invalidate(ownedNetworksProvider),
        ),
      ),
    );
  }
}

/// بطاقات الملخّص التجاري الثلاث.
class _CommercialSummarySection extends ConsumerWidget {
  final String? networkId;

  const _CommercialSummarySection({required this.networkId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(commercialSummaryProvider(networkId));

    return summaryAsync.when(
      data: (summary) {
        return Row(
          children: [
            Expanded(
              child: _SummaryCard(
                icon: Icons.attach_money,
                label: 'إجمالي المبيعات',
                value: '${summary['gross_sales']}',
                color: AppTheme.info,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SummaryCard(
                icon: Icons.pending_actions,
                label: 'قيد التسوية',
                value: '${summary['pending_settlement']}',
                color: AppTheme.warning,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SummaryCard(
                icon: Icons.shopping_cart,
                label: 'مباع',
                value: '${summary['total_sold']}',
                color: AppTheme.accentDark,
              ),
            ),
          ],
        );
      },
      loading: () => const SizedBox(
        height: 80,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => const Card(
        color: Color(0x14E74C3C), // AppTheme.error with alpha 0.08
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'تعذّر تحميل الملخّص التجاري',
            style: TextStyle(color: AppTheme.error, fontSize: 13),
          ),
        ),
      ),
    );
  }
}

/// بطاقة ملخّص صغيرة (رقم واحد).
class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// قائمة التسويات.
class _SettlementsList extends ConsumerWidget {
  final String? networkId;

  const _SettlementsList({required this.networkId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settlementsAsync = ref.watch(settlementsProvider(networkId));

    return settlementsAsync.when(
      data: (settlements) {
        if (settlements.isEmpty) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(Icons.receipt_long_outlined, size: 48, color: AppTheme.textMuted),
                  SizedBox(height: 8),
                  Text(
                    'لا توجد تسويات بعد',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
          );
        }

        return Column(
          children: settlements.map((s) => _SettlementCard(settlement: s)).toList(),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Card(
        color: Color(0x14E74C3C), // AppTheme.error with alpha 0.08
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'تعذّر تحميل التسويات',
            style: TextStyle(color: AppTheme.error, fontSize: 13),
          ),
        ),
      ),
    );
  }
}

/// بطاقة تسوية واحدة.
class _SettlementCard extends StatelessWidget {
  final Map<String, dynamic> settlement;

  const _SettlementCard({required this.settlement});

  Color _statusColor() {
    switch (settlement['status']) {
      case 'paid':
        return AppTheme.accentDark;
      case 'approved':
        return AppTheme.info;
      case 'draft':
      case 'ready_for_review':
        return AppTheme.warning;
      case 'cancelled':
      case 'corrected':
        return AppTheme.error;
      default:
        return AppTheme.textMuted;
    }
  }

  String _statusLabel() {
    switch (settlement['status']) {
      case 'paid':
        return 'مدفوعة';
      case 'approved':
        return 'معتمدة';
      case 'draft':
        return 'مسودة';
      case 'ready_for_review':
        return 'قيد المراجعة';
      case 'cancelled':
        return 'ملغاة';
      case 'corrected':
        return 'معدّلة';
      default:
        return settlement['status']?.toString() ?? '—';
    }
  }

  String _formatDate(dynamic dateStr) {
    if (dateStr == null) return '—';
    try {
      final dt = DateTime.parse(dateStr.toString());
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return dateStr.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SettlementDetailScreen(settlement: settlement),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ───── الصف العلوي: فترة + حالة ─────
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_formatDate(settlement['period_start'])} ← ${_formatDate(settlement['period_end'])}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                      ),
                    ),
                    AppTheme.statusChip(
                      _statusLabel(),
                      color: color.withValues(alpha: 0.12),
                      textColor: color,
                    ),
                ],
              ),

              const SizedBox(height: 10),

              // ───── الأرقام ─────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _miniStat('إجمالي', settlement['gross_sales']),
                  _miniStat('عمولة', settlement['total_commission']),
                  _miniStat('صافي', settlement['net_settlement'],
                      bold: true, color: AppTheme.accentDark),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniStat(String label, dynamic value, {bool bold = false, Color? color}) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
        ),
        Text(
          '${value ?? 0}',
          style: TextStyle(
            fontSize: 14,
            fontWeight: bold ? FontWeight.bold : FontWeight.w500,
            color: color ?? AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }
}
