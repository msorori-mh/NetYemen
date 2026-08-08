// lib/screens/wallet/deposit_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/utils/uuid_generator.dart';
import '../../providers/app_providers.dart';
import '../../utils/app_theme.dart';

class DepositScreen extends ConsumerStatefulWidget {
  const DepositScreen({super.key});

  @override
  ConsumerState<DepositScreen> createState() => _DepositScreenState();
}

class _DepositScreenState extends ConsumerState<DepositScreen> {
  final _amountController = TextEditingController();
  String _selectedMethod = 'bank_transfer';
  bool _isSubmitting = false;

  final List<Map<String, dynamic>> _methods = [
    {
      'id': 'bank_transfer',
      'name': 'تحويل بنكي',
      'icon': Icons.account_balance
    },
    {'id': 'ewallet', 'name': 'محفظة إلكترونية', 'icon': Icons.phone_android},
    {'id': 'agent', 'name': 'وكيل شحن', 'icon': Icons.storefront},
  ];

  Future<void> _submitRequest() async {
    final amount = int.tryParse(_amountController.text);
    if (amount == null || amount < 100) {
      _showError('الحد الأدنى للشحن 100 ر.ي');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final user = ref.read(currentUserProvider);
      if (user == null) throw Exception('Not authenticated');

      final service = ref.read(supabaseServiceProvider);
      await service.createDepositRequest(
        amount: amount,
        proofReference: _selectedMethod,
        idempotencyKey: UuidGenerator.generateV4(),
      );

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('تم إرسال الطلب'),
          content: const Text('سيتم مراجعة طلبك والتأكيد خلال دقائق'),
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
      _showError('فشل إرسال الطلب');
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('شحن المحفظة'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'المبلغ',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
            const Text(
              'طريقة الدفع',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ..._methods.map((method) {
              final isSelected = _selectedMethod == method['id'];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                color:
                    isSelected ? AppTheme.primary.withValues(alpha: 0.1) : null,
                child: ListTile(
                  leading: Icon(
                    method['icon'] as IconData,
                    color:
                        isSelected ? AppTheme.primary : AppTheme.textSecondary,
                  ),
                  title: Text(method['name'] as String),
                  trailing: isSelected
                      ? const Icon(Icons.check_circle, color: AppTheme.primary)
                      : null,
                  onTap: () {
                    setState(() {
                      _selectedMethod = method['id'] as String;
                    });
                  },
                ),
              );
            }),
            const Spacer(),
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
}
