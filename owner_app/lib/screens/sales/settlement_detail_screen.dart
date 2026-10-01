// lib/screens/sales/settlement_detail_screen.dart
import 'package:flutter/material.dart';

import '../../utils/app_theme.dart';

/// شاشة تفاصيل تسوية واحدة — F-OWN-06.
///
/// تعرض كل حقول التسوية (gross_sales, total_commission, total_refunds,
/// total_adjustments, net_settlement, status, notes) وبنود التسوية (lines[]).
class SettlementDetailScreen extends StatelessWidget {
  final Map<String, dynamic> settlement;

  const SettlementDetailScreen({super.key, required this.settlement});

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
    final lines = settlement['lines'] as List? ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('تفاصيل التسوية'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ───── بطاقة المعلومات الأساسية ─────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoRow('الفترة',
                      '${_formatDate(settlement['period_start'])} ← ${_formatDate(settlement['period_end'])}'),
                  _infoRow('الحالة', settlement['status']?.toString() ?? '—'),
                  _infoRow('تاريخ الإنشاء', _formatDate(settlement['created_at'])),
                  if (settlement['reviewed_at'] != null)
                    _infoRow('تاريخ المراجعة', _formatDate(settlement['reviewed_at'])),
                  if (settlement['notes'] != null &&
                      (settlement['notes'] as String).isNotEmpty)
                    _infoRow('ملاحظات', settlement['notes'].toString()),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ───── بطاقة الأرقام المالية ─────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'التفاصيل المالية',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const Divider(),
                  _finRow('إجمالي المبيعات', settlement['gross_sales']),
                  _finRow('العمولة', settlement['total_commission'],
                      color: AppTheme.warning, negative: true),
                  _finRow('المرتجعات', settlement['total_refunds'],
                      color: AppTheme.error, negative: true),
                  _finRow('التعديلات', settlement['total_adjustments']),
                  const Divider(),
                  _finRow('الصافي المستحق', settlement['net_settlement'],
                      color: AppTheme.accentDark, bold: true),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ───── بنود التسوية ─────
          if (lines.isNotEmpty) ...[
            Text(
              'بنود التسوية (${lines.length})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 8),
            ...lines.map((line) => _SettlementLineCard(line: Map<String, dynamic>.from(line as Map))),
          ] else
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    'لا توجد بنود تفصيلية',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _finRow(String label, dynamic value,
      {Color? color, bool bold = false, bool negative = false}) {
    final num = value ?? 0;
    final display = negative && num != 0 ? '-$num' : '$num';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14)),
          Text(
            display,
            style: TextStyle(
              fontSize: 14,
              fontWeight: bold ? FontWeight.bold : FontWeight.w500,
              color: color ?? AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// بطاقة بند تسوية واحد.
class _SettlementLineCard extends StatelessWidget {
  final Map<String, dynamic> line;

  const _SettlementLineCard({required this.line});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // عرض كل مفاتيح البند بشكل عام (defensive — الأعمدة غير مضمونة 100%)
            ...line.entries
                .where((e) => e.value != null)
                .map((e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 130,
                            child: Text(
                              e.key,
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              '${e.value}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    )),
          ],
        ),
      ),
    );
  }
}
