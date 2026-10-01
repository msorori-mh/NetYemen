// lib/features/wallet/presentation/deposit_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../finance/data/finance_providers.dart';
import 'wallet_providers.dart';

class DepositScreen extends ConsumerStatefulWidget {
  const DepositScreen({super.key});

  @override
  ConsumerState<DepositScreen> createState() => _DepositScreenState();
}

class _DepositScreenState extends ConsumerState<DepositScreen> {
  final _amountController = TextEditingController();
  String? _selectedDestinationId;
  final _referenceController = TextEditingController();
  String? _message;

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = int.tryParse(_amountController.text.trim()) ?? 0;
    if (amount <= 0) {
      setState(() => _message = 'أدخل مبلغاً صحيحاً');
      return;
    }
    if (_selectedDestinationId == null) {
      setState(() => _message = 'اختر وجهة الدفع أولاً');
      return;
    }

    setState(() => _message = null);

    try {
      await ref.read(depositSubmissionProvider.notifier).submit(
            amount: amount,
            paymentDestinationId: _selectedDestinationId!,
            proofReference: _referenceController.text.trim().isEmpty
                ? null
                : _referenceController.text.trim(),
          );
      if (mounted) {
        setState(() => _message = 'تم إرسال طلب الإيداع بنجاح');
        _amountController.clear();
        _referenceController.clear();
        _selectedDestinationId = null;
      }
      ref.invalidate(depositHistoryProvider);
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'تعذر تأكيد إرسال الطلب. تحقق من الاتصال ثم أعد المحاولة؛ لن يتكرر الطلب.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final destinationsAsync = ref.watch(activePaymentDestinationsProvider);
    final submissionAsync = ref.watch(depositSubmissionProvider);
    final isSubmitting = submissionAsync.isLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('طلب إيداع')),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'المبلغ (ريال يمني)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            destinationsAsync.when(
              data: (destinations) {
                if (destinations.isEmpty) {
                  return const Text(
                    'لا توجد وجهات دفع مفعلة حالياً (OD-FIN-03).',
                    style: TextStyle(color: Colors.orange),
                  );
                }
                return InputDecorator(
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'وجهة الدفع',
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedDestinationId,
                      hint: const Text('اختر وجهة الدفع'),
                      isExpanded: true,
                      items: destinations.map((destination) {
                        return DropdownMenuItem(
                          value: destination['id'] as String? ?? '',
                          child: Text(
                            destination['display_name'] as String? ?? 'وجهة',
                          ),
                        );
                      }).toList(),
                      onChanged: (value) =>
                          setState(() => _selectedDestinationId = value),
                    ),
                  ),
                );
              },
              loading: () => const CircularProgressIndicator(),
              error: (_, __) => const Text(
                'تعذر تحميل وجهات الدفع. تحقق من الاتصال وأعد فتح الصفحة.',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _referenceController,
              decoration: const InputDecoration(
                labelText: 'رقم المرجع / إيصال الدفع',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: isSubmitting ? null : _submit,
              child: isSubmitting
                  ? const CircularProgressIndicator()
                  : const Text('إرسال الطلب'),
            ),
            if (_message != null) ...[
              const SizedBox(height: 16),
              Text(
                _message!,
                style: TextStyle(
                  color: _message!.startsWith('تم') ? Colors.green : Colors.red,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
