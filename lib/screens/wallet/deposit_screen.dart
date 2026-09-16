// lib/screens/wallet/deposit_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/payment_destination_model.dart';
import '../../providers/app_providers.dart';
import '../../utils/app_theme.dart';

/// طلب شحن المحفظة.
///
/// وجهات الدفع تأتي من `get_active_payment_destinations()` ولا تُكتب في
/// التطبيق: الإدارة تضيفها وترتّبها من لوحة التحكم.
class DepositScreen extends ConsumerStatefulWidget {
  const DepositScreen({super.key});

  @override
  ConsumerState<DepositScreen> createState() => _DepositScreenState();
}

class _DepositScreenState extends ConsumerState<DepositScreen> {
  final _amountController = TextEditingController();
  final _referenceController = TextEditingController();
  PaymentDestination? _selected;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  Future<void> _submitRequest() async {
    final amount = int.tryParse(_amountController.text.trim());
    if (amount == null || amount < 100) {
      _showError('الحد الأدنى للشحن 100 ر.ي');
      return;
    }

    final destination = _selected;
    if (destination == null) {
      _showError('اختر وجهة الدفع التي حوّلت إليها');
      return;
    }

    final reference = _referenceController.text.trim();
    if (reference.isEmpty) {
      _showError('أدخل رقم الحوالة المرجعي');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final service = ref.read(supabaseServiceProvider);
      await service.createDepositRequest(
        amount: amount,
        referenceNumber: reference,
        paymentDestinationId: destination.id,
      );

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('تم إرسال الطلب'),
          content: const Text(
            'سيراجع فريق المالية الحوالة ويُضاف المبلغ إلى محفظتك بعد التأكيد.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
              child: const Text('حسناً'),
            ),
          ],
        ),
      );
    } catch (e) {
      _showError(_depositErrorText(e));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String _depositErrorText(Object e) {
    final raw = e.toString();
    if (raw.contains('DUPLICATE_REFERENCE')) {
      return 'رقم الحوالة هذا مُستخدم في طلب سابق';
    }
    if (raw.contains('INVALID_AMOUNT')) return 'المبلغ غير صالح';
    return 'فشل إرسال الطلب: $raw';
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final destinationsAsync = ref.watch(paymentDestinationsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('شحن المحفظة')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'المبلغ',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: 'أدخل المبلغ بالريال اليمني',
                suffixText: 'ر.ي',
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'وجهة الدفع',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            destinationsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Icon(Icons.error_outline_rounded, size: 48, color: AppTheme.error),
                      const SizedBox(height: 8),
                      Text('تعذّر تحميل وجهات الدفع', style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                ),
              ),
              data: (destinations) => destinations.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'لا توجد وجهات دفع مفعّلة حالياً',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.textMuted),
                        ),
                      ),
                    )
                  : Column(
                      children: destinations.map((d) => _destinationTile(d)).toList(),
                    ),
            ),
            const SizedBox(height: 24),
            Text(
              'رقم الحوالة',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _referenceController,
              decoration: const InputDecoration(
                hintText: 'الرقم المرجعي في إشعار التحويل',
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitRequest,
                child: _isSubmitting
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('إرسال طلب الشحن'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _destinationTile(PaymentDestination destination) {
    final isSelected = _selected?.id == destination.id;
    final subtitle = [
      destination.accountHolderName,
      destination.accountIdentifier,
    ].where((t) => t != null && t.isNotEmpty).join(' - ');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isSelected ? AppTheme.primarySoft : null,
      child: ListTile(
        leading: Icon(
          _iconFor(destination.providerType),
          color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
        ),
        title: Text(destination.displayName),
        subtitle: subtitle.isEmpty ? null : Text(subtitle),
        trailing: isSelected
            ? const Icon(Icons.check_circle, color: AppTheme.primary)
            : null,
        onTap: () => setState(() => _selected = destination),
      ),
    );
  }

  IconData _iconFor(String providerType) {
    switch (providerType) {
      case 'mobile_wallet':
        return Icons.phone_android;
      case 'exchange':
        return Icons.storefront;
      case 'bank_account':
      default:
        return Icons.account_balance;
    }
  }
}
