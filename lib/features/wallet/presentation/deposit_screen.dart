// lib/features/wallet/presentation/deposit_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../finance/presentation/finance_providers.dart';
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
  bool _submitting = false;
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

    setState(() {
      _submitting = true;
      _message = null;
    });

    try {
      final repo = ref.read(walletRepositoryProvider);
      await repo.createDepositRequest(
        amount: amount,
        paymentDestinationId: _selectedDestinationId,
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
    } catch (e) {
      if (mounted) {
        setState(() => _message = 'فشل الإرسال: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final destinationsAsync = ref.watch(activePaymentDestinationsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('طلب إيداع')),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                error: (e, _) => Text('خطأ في وجهات الدفع: $e'),
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
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const CircularProgressIndicator()
                    : const Text('إرسال الطلب'),
              ),
              if (_message != null) ...[
                const SizedBox(height: 16),
                Text(
                  _message!,
                  style: TextStyle(
                    color: _message!.startsWith('تم')
                        ? Colors.green
                        : Colors.red,
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
