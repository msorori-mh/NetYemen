// lib/features/finance/presentation/deposit_detail_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'finance_providers.dart';

class DepositDetailScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> deposit;

  const DepositDetailScreen({super.key, required this.deposit});

  @override
  ConsumerState<DepositDetailScreen> createState() =>
      _DepositDetailScreenState();
}

class _DepositDetailScreenState extends ConsumerState<DepositDetailScreen> {
  final _notesController = TextEditingController();
  bool _processing = false;
  String? _message;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _review(String action) async {
    setState(() {
      _processing = true;
      _message = null;
    });

    try {
      final repo = ref.read(financeRepositoryProvider);
      await repo.reviewDeposit(
        widget.deposit['id'] as String,
        action,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );
      if (mounted) {
        setState(() => _message = 'تم تحديث الحالة');
      }
      ref.invalidate(depositQueueProvider(null));
    } catch (e) {
      if (mounted) {
        setState(() => _message = 'فشل التحديث: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.deposit['status'] as String;

    return Scaffold(
      appBar: AppBar(title: const Text('تفاصيل الإيداع')),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'المبلغ: ${widget.deposit['amount']} ${widget.deposit['currency']}',
              ),
              Text('الحالة: $status'),
              Text('المرجع: ${widget.deposit['proof_reference'] ?? '-'}'),
              const SizedBox(height: 16),
              TextField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات المراجعة',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              if (status == 'submitted' || status == 'under_review') ...[
                ElevatedButton(
                  onPressed: _processing ? null : () => _review('approve'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                  ),
                  child: const Text('قبول وشحن الرصيد'),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _processing ? null : () => _review('reject'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text('رفض'),
                ),
              ],
              if (_message != null) ...[
                const SizedBox(height: 16),
                Text(
                  _message!,
                  style: TextStyle(
                    color:
                        _message!.startsWith('تم') ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
