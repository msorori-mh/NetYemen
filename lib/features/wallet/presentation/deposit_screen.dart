// lib/features/wallet/presentation/deposit_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/digits.dart';
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
  final _formKey = GlobalKey<FormState>();
  String? _message;

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final formValid = _formKey.currentState?.validate() ?? false;
    if (_selectedDestinationId == null) {
      setState(() => _message = 'اختر وجهة الدفع أولاً');
      return;
    }
    if (!formValid) {
      setState(() => _message = null);
      return;
    }
    final amount = parseDepositAmount(_amountController.text)!;

    setState(() => _message = null);

    try {
      await ref.read(depositSubmissionProvider.notifier).submit(
            amount: amount,
            paymentDestinationId: _selectedDestinationId!,
            proofReference: _referenceController.text.trim(),
          );
      if (mounted) {
        setState(() => _message = 'تم إرسال طلب الإيداع بنجاح');
        _amountController.clear();
        _referenceController.clear();
        _selectedDestinationId = null;
      }
    } catch (error) {
      if (mounted) {
        setState(() => _message = depositErrorMessage(error));
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
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              TextFormField(
                key: const Key('deposit-amount'),
                controller: _amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'المبلغ (ريال يمني)',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => parseDepositAmount(value ?? '') == null
                    ? 'أدخل مبلغاً صحيحاً'
                    : null,
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
              TextFormField(
                key: const Key('deposit-reference'),
                controller: _referenceController,
                decoration: const InputDecoration(
                  labelText: 'رقم المرجع / إيصال الدفع',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => (value ?? '').trim().isEmpty
                    ? 'أدخل رقم المرجع الظاهر في إيصال التحويل'
                    : null,
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

/// Parses the deposit amount, accepting Arabic-Indic and Persian digits.
/// Returns null unless the input is a positive whole number.
int? parseDepositAmount(String input) {
  final amount = int.tryParse(normalizeDigits(input.trim()));
  return amount != null && amount > 0 ? amount : null;
}

/// Maps create_wallet_deposit_request error codes to customer messages.
String depositErrorMessage(Object error) {
  final message = error.toString();
  if (message.contains('INVALID_REFERENCE')) {
    return 'رقم المرجع مطلوب. أدخل رقم المرجع الظاهر في إيصال التحويل.';
  }
  if (message.contains('DUPLICATE_REFERENCE')) {
    return 'رقم المرجع هذا مستخدم في إيداع سابق. تحقق من الرقم.';
  }
  if (message.contains('INVALID_AMOUNT')) {
    return 'أدخل مبلغاً صحيحاً أكبر من صفر.';
  }
  if (message.contains('PAYMENT_DESTINATION_REQUIRED') ||
      message.contains('INVALID_PAYMENT_DESTINATION')) {
    return 'وجهة الدفع غير متاحة حالياً. اختر وجهة أخرى.';
  }
  if (message.contains('DEPOSIT_ALREADY_IN_PROGRESS')) {
    return 'يوجد طلب إيداع آخر قيد الإرسال. انتظر اكتماله ثم حاول مجدداً.';
  }
  if (message.contains('INACTIVE_PROFILE')) {
    return 'حسابك غير نشط حالياً. تواصل مع الدعم.';
  }
  if (message.contains('UNAUTHENTICATED')) {
    return 'انتهت جلسة الدخول. سجّل الدخول ثم حاول مجدداً.';
  }
  return 'تعذر تأكيد إرسال الطلب. تحقق من الاتصال ثم أعد المحاولة؛ لن يتكرر الطلب.';
}
