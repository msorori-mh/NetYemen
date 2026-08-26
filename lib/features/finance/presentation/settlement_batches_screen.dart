// lib/features/finance/presentation/settlement_batches_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/finance_operation_policy.dart';
import 'finance_providers.dart';
import 'settlement_detail_screen.dart';

class SettlementBatchesScreen extends ConsumerStatefulWidget {
  const SettlementBatchesScreen({super.key});

  @override
  ConsumerState<SettlementBatchesScreen> createState() =>
      _SettlementBatchesScreenState();
}

class _SettlementBatchesScreenState
    extends ConsumerState<SettlementBatchesScreen> {
  String? _statusFilter;

  @override
  Widget build(BuildContext context) {
    final batchesAsync = ref.watch(settlementBatchesProvider(_statusFilter));

    return Scaffold(
      appBar: AppBar(
        title: const Text('دفعات التسوية'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.invalidate(settlementBatchesProvider(_statusFilter)),
          ),
        ],
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          children: [
            _StatusFilter(
              selected: _statusFilter,
              onChanged: (value) => setState(() => _statusFilter = value),
            ),
            Expanded(
              child: batchesAsync.when(
                data: (batches) =>
                    _BatchList(batches: batches, statusFilter: _statusFilter),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => const Center(
                  child: Text('تعذر تحميل دفعات التسوية. حاول مرة أخرى.'),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openCreateDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _openCreateDialog(BuildContext context) {
    showDialog(context: context, builder: (_) => const _CreateBatchDialog());
  }
}

class _StatusFilter extends StatelessWidget {
  final String? selected;
  final ValueChanged<String?> onChanged;

  const _StatusFilter({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final statuses = [
      (null, 'الكل'),
      ('draft', 'مسودة'),
      ('ready_for_review', 'جاهز للمراجعة'),
      ('approved', 'معتمد'),
      ('paid', 'مدفوع'),
      ('cancelled', 'ملغي'),
      ('corrected', 'مصحح'),
    ];

    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: statuses.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final (value, label) = statuses[index];
          final isSelected = value == selected;
          return ChoiceChip(
            label: Text(label),
            selected: isSelected,
            onSelected: (_) => onChanged(value),
          );
        },
      ),
    );
  }
}

class _BatchList extends ConsumerWidget {
  final List<Map<String, dynamic>> batches;
  final String? statusFilter;

  const _BatchList({required this.batches, this.statusFilter});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (batches.isEmpty) {
      return const Center(child: Text('لا توجد دفعات تسوية'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: batches.length,
      itemBuilder: (context, index) {
        final batch = batches[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            title: Text(batch['network_name'] as String? ?? 'شبكة'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('المالك: ${batch['owner_name'] ?? '-'}'),
                Text(
                  'الفترة: ${batch['period_start']} إلى ${batch['period_end']}',
                ),
                Text(
                  'الإجمالي: ${batch['gross_sales']} | العمولة: ${batch['total_commission']} | الصافي: ${batch['net_settlement']}',
                ),
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

class _CreateBatchDialog extends ConsumerStatefulWidget {
  const _CreateBatchDialog();

  @override
  ConsumerState<_CreateBatchDialog> createState() => _CreateBatchDialogState();
}

class _CreateBatchDialogState extends ConsumerState<_CreateBatchDialog> {
  DateTime _periodStart = DateTime.now().subtract(const Duration(days: 7));
  DateTime _periodEnd = DateTime.now();
  bool _creating = false;
  String? _message;

  Future<void> _pickDate(bool start) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: start ? _periodStart : _periodEnd,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        if (start) {
          _periodStart = picked;
        } else {
          _periodEnd = picked;
        }
      });
    }
  }

  Future<void> _create() async {
    if (!FinanceOperationPolicy.isValidSettlementPeriod(
      _periodStart,
      _periodEnd,
    )) {
      setState(() {
        _message = 'يجب أن تكون بداية الفترة قبل نهايتها أو مساوية لها.';
      });
      return;
    }

    setState(() {
      _creating = true;
      _message = null;
    });

    try {
      final repo = ref.read(financeRepositoryProvider);
      await repo.createSettlementBatch(
        periodStart: _periodStart,
        periodEnd: _periodEnd,
      );
      ref.invalidate(settlementBatchesProvider(null));
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = 'تعذر إنشاء دفعة التسوية. تحقق من الفترة وحاول مجدداً.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _creating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('إنشاء دفعة تسوية'),
      content: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('بداية الفترة'),
              subtitle: Text(
                '${_periodStart.year}-${_periodStart.month}-${_periodStart.day}',
              ),
              trailing: const Icon(Icons.calendar_today),
              onTap: () => _pickDate(true),
            ),
            ListTile(
              title: const Text('نهاية الفترة'),
              subtitle: Text(
                '${_periodEnd.year}-${_periodEnd.month}-${_periodEnd.day}',
              ),
              trailing: const Icon(Icons.calendar_today),
              onTap: () => _pickDate(false),
            ),
            if (_message != null)
              Text(_message!, style: const TextStyle(color: Colors.red)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _creating ? null : () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: _creating ? null : _create,
          child: _creating
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('إنشاء'),
        ),
      ],
    );
  }
}
