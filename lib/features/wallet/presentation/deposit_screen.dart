// lib/features/wallet/presentation/deposit_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'wallet_providers.dart';

class DepositScreen extends ConsumerStatefulWidget {
  const DepositScreen({super.key});

  @override
  ConsumerState<DepositScreen> createState() => _DepositScreenState();
}

class _DepositScreenState extends ConsumerState<DepositScreen> {
  final _amountController = TextEditingController();
  String? _selectedChannelId;
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

    setState(() {
      _submitting = true;
      _message = null;
    });

    try {
      final repo = ref.read(walletRepositoryProvider);
      await repo.createDepositRequest(
        amount: amount,
        channelId: _selectedChannelId,
        proofReference: _referenceController.text.trim().isEmpty
            ? null
            : _referenceController.text.trim(),
      );
      if (mounted) {
        setState(() => _message = 'تم إرسال طلب الإيداع بنجاح');
        _amountController.clear();
        _referenceController.clear();
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
    final channelsAsync = ref.watch(depositChannelsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('طلب إيداع'),
      ),
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
              channelsAsync.when(
                data: (channels) {
                  if (channels.isEmpty) {
                    return const Text(
                      'لا توجد قنوات إيداء مفعلة حالياً (OD-FIN-03).',
                      style: TextStyle(color: Colors.orange),
                    );
                  }
                  return InputDecorator(
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'قناة الإيداع',
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedChannelId,
                        hint: const Text('اختر قناة الإيداع'),
                        isExpanded: true,
                        items: channels.map((channel) {
                          return DropdownMenuItem(
                            value: channel.id,
                            child: Text(channel.displayName),
                          );
                        }).toList(),
                        onChanged: (value) => setState(() => _selectedChannelId = value),
                      ),
                    ),
                  );
                },
                loading: () => const CircularProgressIndicator(),
                error: (e, _) => Text('خطأ في القنوات: $e'),
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
                    color: _message!.startsWith('تم') ? Colors.green : Colors.red,
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
