// lib/features/wallet/presentation/deposit_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/digit_input_formatter.dart';
import '../../../core/utils/digits.dart';
import '../../../core/utils/money_format.dart';
import '../../finance/data/finance_providers.dart';
import 'wallet_providers.dart';

class DepositScreen extends ConsumerStatefulWidget {
  const DepositScreen({super.key});

  @override
  ConsumerState<DepositScreen> createState() => _DepositScreenState();
}

class _DepositScreenState extends ConsumerState<DepositScreen> {
  static const _referenceRequired = 'رقم المرجع مطلوب. انسخه من إيصال التحويل.';

  final _amountController = TextEditingController();
  final _referenceController = TextEditingController();
  String? _selectedDestinationId;
  String? _amountError;
  String? _destinationError;
  String? _referenceError;
  String? _message;
  bool _messageIsSuccess = false;

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  /// Destinations that can actually be chosen (a row without an id cannot be
  /// submitted, so it is never offered).
  List<Map<String, dynamic>> _selectable(List<Map<String, dynamic>> rows) {
    final seen = <String>{};
    return [
      for (final row in rows)
        if (_idOf(row).isNotEmpty && seen.add(_idOf(row))) row,
    ];
  }

  static String _idOf(Map<String, dynamic> row) => row['id'] as String? ?? '';

  static String _textOf(Map<String, dynamic> row, String field) =>
      (row[field] as String? ?? '').trim();

  /// The chosen destination, or the only one when a single destination is
  /// active. A selection that is no longer offered is ignored.
  Map<String, dynamic>? _effectiveDestination(
    List<Map<String, dynamic>> destinations,
  ) {
    for (final destination in destinations) {
      if (_idOf(destination) == _selectedDestinationId) return destination;
    }
    return destinations.length == 1 ? destinations.first : null;
  }

  Future<void> _submit() async {
    final amount = parseWholeAmount(_amountController.text);
    final reference = _referenceController.text.trim();
    final destinations = _selectable(
      ref.read(activePaymentDestinationsProvider).valueOrNull ?? const [],
    );
    final destination = _effectiveDestination(destinations);

    final amountError = amount == null || amount <= 0
        ? 'أدخل مبلغاً صحيحاً بالريال اليمني (أرقام فقط).'
        : null;
    final destinationError =
        destination == null ? 'اختر وجهة الدفع التي حوّلت إليها.' : null;
    final referenceError = reference.isEmpty ? _referenceRequired : null;

    setState(() {
      _amountError = amountError;
      _destinationError = destinationError;
      _referenceError = referenceError;
      _message = null;
    });
    if (amount == null ||
        amountError != null ||
        destination == null ||
        referenceError != null) {
      return;
    }

    try {
      await ref.read(depositSubmissionProvider.notifier).submit(
            amount: amount,
            paymentDestinationId: _idOf(destination),
            referenceNumber: reference,
          );
      if (!mounted) return;
      ref.invalidate(depositHistoryProvider);
      _amountController.clear();
      _referenceController.clear();
      setState(() {
        _selectedDestinationId = null;
        _messageIsSuccess = true;
        _message =
            'تم إرسال طلب إيداع بمبلغ ${formatYer(amount)}. سيُضاف الرصيد بعد مراجعة التحويل.';
      });
    } catch (error) {
      if (!mounted) return;
      if (isDepositDestinationError(error)) {
        ref.invalidate(activePaymentDestinationsProvider);
      }
      setState(() {
        _messageIsSuccess = false;
        _message = depositErrorMessage(error);
        if (isDepositReferenceError(error)) {
          _referenceError = _referenceRequired;
        }
      });
    }
  }

  Future<void> _copyAccountIdentifier(String identifier) async {
    await Clipboard.setData(ClipboardData(text: identifier));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم نسخ رقم الحساب')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final destinationsAsync = ref.watch(activePaymentDestinationsProvider);
    final submissionAsync = ref.watch(depositSubmissionProvider);
    final isSubmitting = submissionAsync.isLoading;
    final message = _message;

    return Scaffold(
      appBar: AppBar(title: const Text('طلب إيداع')),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            const Text(
              'حوّل المبلغ إلى إحدى وجهات الدفع أدناه، ثم أدخل المبلغ ورقم مرجع التحويل ليراجعه فريق المالية.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            destinationsAsync.when(
              data: (rows) => _buildDestinations(_selectable(rows)),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'تعذر تحميل وجهات الدفع. تحقق من الاتصال ثم أعد المحاولة.',
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () =>
                        ref.invalidate(activePaymentDestinationsProvider),
                    icon: const Icon(Icons.refresh),
                    label: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('deposit-amount-field'),
              controller: _amountController,
              keyboardType: TextInputType.number,
              inputFormatters: const [
                LocalizedDigitsInputFormatter(maxLength: 9),
              ],
              decoration: InputDecoration(
                labelText: 'المبلغ (ريال يمني)',
                border: const OutlineInputBorder(),
                errorText: _amountError,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('deposit-reference-field'),
              controller: _referenceController,
              maxLength: 64,
              decoration: InputDecoration(
                labelText: 'رقم المرجع / إيصال الدفع (مطلوب)',
                helperText: 'الرقم الظاهر في إيصال أو إشعار التحويل.',
                border: const OutlineInputBorder(),
                counterText: '',
                errorText: _referenceError,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              key: const Key('deposit-submit'),
              onPressed: isSubmitting ? null : _submit,
              child: isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('إرسال الطلب'),
            ),
            if (message != null) ...[
              const SizedBox(height: 16),
              Text(
                message,
                key: const Key('deposit-message'),
                style: TextStyle(
                  color: _messageIsSuccess ? Colors.green : Colors.red,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDestinations(List<Map<String, dynamic>> destinations) {
    if (destinations.isEmpty) {
      return const Text(
        'لا توجد وجهات دفع مفعلة حالياً. حاول لاحقاً أو تواصل مع الدعم.',
        style: TextStyle(color: Colors.orange),
      );
    }

    final selected = _effectiveDestination(destinations);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InputDecorator(
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: 'وجهة الدفع',
            errorText: _destinationError,
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              key: const Key('deposit-destination-dropdown'),
              value: selected == null ? null : _idOf(selected),
              hint: const Text('اختر وجهة الدفع'),
              isExpanded: true,
              items: [
                for (final destination in destinations)
                  DropdownMenuItem<String>(
                    value: _idOf(destination),
                    child: Text(
                      _textOf(destination, 'display_name').isEmpty
                          ? 'وجهة'
                          : _textOf(destination, 'display_name'),
                    ),
                  ),
              ],
              onChanged: (value) => setState(() {
                _selectedDestinationId = value;
                _destinationError = null;
              }),
            ),
          ),
        ),
        if (selected != null) ...[
          const SizedBox(height: 12),
          _DestinationDetails(
            accountHolderName: _textOf(selected, 'account_holder_name'),
            accountIdentifier: _textOf(selected, 'account_identifier'),
            instructions: _textOf(selected, 'instructions'),
            onCopyIdentifier: _copyAccountIdentifier,
          ),
        ],
      ],
    );
  }
}

/// Where the customer must send the money: account identifier (copyable),
/// account holder and the destination's own instructions.
class _DestinationDetails extends StatelessWidget {
  final String accountHolderName;
  final String accountIdentifier;
  final String instructions;
  final ValueChanged<String> onCopyIdentifier;

  const _DestinationDetails({
    required this.accountHolderName,
    required this.accountIdentifier,
    required this.instructions,
    required this.onCopyIdentifier,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('deposit-destination-details'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'بيانات التحويل',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (accountIdentifier.isEmpty)
              const Text(
                'لم يُحدَّد رقم حساب لهذه الوجهة. تواصل مع الدعم قبل التحويل.',
                style: TextStyle(color: Colors.orange),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'رقم الحساب / المحفظة',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: SelectableText(
                            accountIdentifier,
                            key: const Key('deposit-account-identifier'),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const Key('deposit-copy-account-identifier'),
                    tooltip: 'نسخ رقم الحساب',
                    onPressed: () => onCopyIdentifier(accountIdentifier),
                    icon: const Icon(Icons.copy),
                  ),
                ],
              ),
            if (accountHolderName.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('اسم صاحب الحساب: $accountHolderName'),
            ],
            if (instructions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(instructions),
            ],
          ],
        ),
      ),
    );
  }
}
