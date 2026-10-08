// lib/features/finance/presentation/settlement_detail_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../data/finance_providers.dart';
import '../domain/finance_operation_policy.dart';

class SettlementDetailScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> batch;

  const SettlementDetailScreen({super.key, required this.batch});

  @override
  ConsumerState<SettlementDetailScreen> createState() =>
      _SettlementDetailScreenState();
}

class _SettlementDetailScreenState
    extends ConsumerState<SettlementDetailScreen> {
  static const _paymentReferenceRequired =
      'مرجع الدفع مطلوب. أدخل رقم مرجع التحويل قبل تسجيل الدفع.';

  bool _processing = false;
  String? _referenceError;
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
              referenceError: _referenceError,
              onApprove: _approve,
              onMarkPaid: _markPaid,
              onCancel: _cancel,
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
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _markPaid() async {
    final reference = _notesController.text.trim();
    if (reference.isEmpty) {
      // The server refuses to mark a batch paid without the transfer
      // reference, so ask for it before anything is sent.
      setState(() => _referenceError = _paymentReferenceRequired);
      return;
    }
    setState(() => _referenceError = null);

    final confirmed = await _confirmAction(
      title: 'تسجيل الدفعة كمدفوعة',
      message: 'هذا الإجراء مالي حساس. تأكد من إتمام التحويل قبل المتابعة.',
      confirmLabel: 'تسجيل الدفع',
    );
    if (!confirmed || !mounted) return;
    setState(() => _processing = true);
    try {
      final repo = ref.read(financeRepositoryProvider);
      await repo.markSettlementPaid(_batchId, paymentReference: reference);
      ref.invalidate(settlementBatchesProvider(null));
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم التسجيل كمدفوع')));
      }
    } catch (error) {
      if (mounted) {
        if (error.toString().contains('PAYMENT_REFERENCE_REQUIRED')) {
          setState(() => _referenceError = _paymentReferenceRequired);
        }
        _showError(error);
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _cancel() async {
    final reason = await _askCancellationReason();
    if (reason == null || !mounted) return;
    setState(() => _processing = true);
    try {
      final repo = ref.read(financeRepositoryProvider);
      await repo.cancelSettlementBatch(_batchId, reason: reason);
      ref.invalidate(settlementBatchesProvider(null));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إلغاء الدفعة وتحرير بنودها')),
        );
        await Navigator.of(context).maybePop();
      }
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  /// Asks for the cancellation reason the server requires. Returns null when
  /// the dialog is dismissed or the reason is left blank.
  Future<String?> _askCancellationReason() async {
    var reason = '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إلغاء دفعة التسوية'),
        content: TextField(
          key: const Key('settlement-cancel-reason'),
          onChanged: (value) => reason = value,
          maxLines: 3,
          maxLength: FinanceOperationPolicy.maximumCancellationReasonLength,
          decoration: const InputDecoration(
            labelText: 'سبب الإلغاء (مطلوب)',
            helperText: 'تعود بنود الدفعة متاحة لدفعة لاحقة.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('تراجع'),
          ),
          FilledButton(
            key: const Key('settlement-cancel-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('تأكيد الإلغاء'),
          ),
        ],
      ),
    );
    if (confirmed != true) return null;

    final trimmed = reason.trim();
    if (trimmed.isNotEmpty) return trimmed;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('سبب الإلغاء مطلوب لإلغاء الدفعة.')),
      );
    }
    return null;
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(settlementErrorMessage(error))),
    );
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

/// Arabic message for a failed settlement action, by server error code.
String settlementErrorMessage(Object error) {
  final message = error.toString();
  if (message.contains('PAYMENT_REFERENCE_REQUIRED')) {
    return 'مرجع الدفع مطلوب. أدخل رقم مرجع التحويل قبل تسجيل الدفع.';
  }
  if (message.contains('PAYMENT_REFERENCE_TOO_LONG')) {
    return 'مرجع الدفع أطول من المسموح. اختصره ثم أعد المحاولة.';
  }
  if (message.contains('REASON_REQUIRED')) {
    return 'سبب الإلغاء مطلوب وبحد أقصى 500 حرف.';
  }
  if (message.contains('INVALID_STATE')) {
    return 'حالة الدفعة تغيّرت ولم تعد تسمح بهذا الإجراء. حدّث القائمة.';
  }
  if (message.contains('NOT_FOUND')) {
    return 'لم يتم العثور على الدفعة. حدّث القائمة ثم حاول مجدداً.';
  }
  if (message.contains('FORBIDDEN') || message.contains('UNAUTHENTICATED')) {
    return 'لا تملك صلاحية تنفيذ هذا الإجراء أو انتهت الجلسة.';
  }
  return 'تعذر تنفيذ عملية التسوية. حاول مرة أخرى.';
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
            if (_isNegative(batch['net_settlement']))
              const Text(
                'الصافي سالب: المرتجعات تتجاوز المبيعات والمبلغ مستحق على المالك.',
                key: Key('settlement-negative-net'),
                style: TextStyle(color: AppTheme.error),
              ),
            if (batch['notes'] != null && (batch['notes'] as String).isNotEmpty)
              _row('ملاحظات', batch['notes'] as String),
          ],
        ),
      ),
    );
  }

  static bool _isNegative(Object? value) => value is num && value < 0;

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
  final String? referenceError;
  final VoidCallback onApprove;
  final VoidCallback onMarkPaid;
  final VoidCallback onCancel;

  const _ActionsSection({
    required this.status,
    required this.processing,
    required this.notesController,
    required this.referenceError,
    required this.onApprove,
    required this.onMarkPaid,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final canApprove = status == 'draft' || status == 'ready_for_review';
    if (!canApprove && status != 'approved') {
      // Paid, cancelled and corrected batches are final.
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (canApprove) ...[
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
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('settlement-cancel'),
                onPressed: processing ? null : onCancel,
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('إلغاء الدفعة'),
              ),
            ],
            if (status == 'approved') ...[
              TextField(
                key: const Key('settlement-payment-reference'),
                controller: notesController,
                maxLength: FinanceOperationPolicy.maximumPaymentNotesLength,
                decoration: InputDecoration(
                  labelText: 'مرجع الدفع (مطلوب)',
                  helperText: 'رقم مرجع التحويل الذي دُفعت به التسوية.',
                  border: const OutlineInputBorder(),
                  errorText: referenceError,
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                key: const Key('settlement-mark-paid'),
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
