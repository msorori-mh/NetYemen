// lib/features/finance/presentation/settlement_detail_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import 'finance_providers.dart';

class SettlementDetailScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> batch;

  const SettlementDetailScreen({super.key, required this.batch});

  @override
  ConsumerState<SettlementDetailScreen> createState() =>
      _SettlementDetailScreenState();
}

class _SettlementDetailScreenState
    extends ConsumerState<SettlementDetailScreen> {
  bool _processing = false;
  final _notesController = TextEditingController();

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  String get _batchId => widget.batch['id'] as String;
  String get _status => widget.batch['status'] as String? ?? 'draft';

  @override
  Widget build(BuildContext context) {
    final lines = (widget.batch['lines'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
        [];

    return Scaffold(
      appBar: AppBar(title: const Text('تفاصيل دفعة التسوية')),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _SummaryCard(batch: widget.batch),
            const SizedBox(height: 16),
            _ActionsSection(
              status: _status,
              processing: _processing,
              notesController: _notesController,
              onApprove: _approve,
              onMarkPaid: _markPaid,
            ),
            const SizedBox(height: 16),
            const Text(
              'بنود الدفعة',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (lines.isEmpty) const Text('لا توجد بنود'),
            ...lines.map((line) => _LineCard(line: line)),
          ],
        ),
      ),
    );
  }

  Future<void> _approve() async {
    final confirmed = await _confirmAction(
      title: 'اعتماد دفعة التسوية',
      message: 'سيتم تثبيت مبالغ الدفعة تمهيداً للدفع. هل تريد المتابعة؟',
      confirmLabel: 'اعتماد',
    );
    if (!confirmed || !mounted) return;
    setState(() => _processing = true);
    try {
      final repo = ref.read(financeRepositoryProvider);
      await repo.approveSettlementBatch(_batchId);
      ref.invalidate(settlementBatchesProvider(null));
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم اعتماد الدفعة')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر تنفيذ عملية التسوية. حاول مرة أخرى.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _markPaid() async {
    final confirmed = await _confirmAction(
      title: 'تسجيل الدفعة كمدفوعة',
      message: 'هذا الإجراء مالي حساس. تأكد من إتمام التحويل قبل المتابعة.',
      confirmLabel: 'تسجيل الدفع',
    );
    if (!confirmed || !mounted) return;
    setState(() => _processing = true);
    try {
      final repo = ref.read(financeRepositoryProvider);
      await repo.markSettlementPaid(
        _batchId,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );
      ref.invalidate(settlementBatchesProvider(null));
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم التسجيل كمدفوع')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر تنفيذ عملية التسوية. حاول مرة أخرى.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<bool> _confirmAction({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(confirmLabel),
              ),
            ],
          ),
        ) ??
        false;
  }
}

class _SummaryCard extends StatelessWidget {
  final Map<String, dynamic> batch;

  const _SummaryCard({required this.batch});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              batch['network_name'] as String? ?? 'شبكة',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _row('المالك', batch['owner_name'] as String? ?? '-'),
            _row(
              'الفترة',
              '${batch['period_start']} إلى ${batch['period_end']}',
            ),
            _row('الحالة', _statusLabel(batch['status'] as String? ?? 'draft')),
            const Divider(height: 24),
            _row('المبيعات', '${batch['gross_sales']}'),
            _row('العمولة', '${batch['total_commission']}'),
            _row('المرتجعات', '${batch['total_refunds']}'),
            _row('التعديلات', '${batch['total_adjustments']}'),
            _row('الصافي', '${batch['net_settlement']}', bold: true),
            if (batch['notes'] != null && (batch['notes'] as String).isNotEmpty)
              _row('ملاحظات', batch['notes'] as String),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
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

class _ActionsSection extends StatelessWidget {
  final String status;
  final bool processing;
  final TextEditingController notesController;
  final VoidCallback onApprove;
  final VoidCallback onMarkPaid;

  const _ActionsSection({
    required this.status,
    required this.processing,
    required this.notesController,
    required this.onApprove,
    required this.onMarkPaid,
  });

  @override
  Widget build(BuildContext context) {
    if (status == 'paid') {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (status == 'draft' || status == 'ready_for_review')
              ElevatedButton.icon(
                onPressed: processing ? null : onApprove,
                icon: const Icon(Icons.check),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.success,
                ),
                label: processing
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('اعتماد الدفعة'),
              ),
            if (status == 'approved') ...[
              TextField(
                controller: notesController,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات الدفع',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: processing ? null : onMarkPaid,
                icon: const Icon(Icons.paid),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.info),
                label: processing
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('تسجيل كمدفوع'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LineCard extends StatelessWidget {
  final Map<String, dynamic> line;

  const _LineCard({required this.line});

  @override
  Widget build(BuildContext context) {
    final type = line['line_type'] as String? ?? 'sale';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              type == 'sale' ? Icons.shopping_cart : Icons.undo,
              color: type == 'sale' ? AppTheme.success : AppTheme.error,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    type == 'sale' ? 'بيع' : 'مرتجع',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'الإجمالي: ${line['gross_amount']} | العمولة: ${line['commission_amount']} | الصافي: ${line['net_amount']}',
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
