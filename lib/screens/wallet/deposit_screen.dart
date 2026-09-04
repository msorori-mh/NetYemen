// lib/screens/wallet/deposit_screen.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/wallet_model.dart';
import '../../providers/app_providers.dart';
import '../../utils/app_theme.dart';

class DepositScreen extends ConsumerStatefulWidget {
  const DepositScreen({super.key});

  @override
  ConsumerState<DepositScreen> createState() => _DepositScreenState();
}

class _DepositScreenState extends ConsumerState<DepositScreen> {
  final _amountController = TextEditingController();
  final _imagePicker = ImagePicker();

  BankAccount? _selectedBank;
  XFile? _receiptFile;
  bool _isSubmitting = false;

  Future<void> _pickReceipt() async {
    final file = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (file != null) {
      setState(() => _receiptFile = file);
    }
  }

  Future<void> _submitRequest() async {
    final amount = int.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      _showError('يرجى إدخال مبلغ صحيح');
      return;
    }
    if (_selectedBank == null) {
      _showError('يرجى اختيار حساب الإيداع');
      return;
    }
    if (_receiptFile == null) {
      _showError('يرجى إرفاق صورة إيصال التحويل');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final user = ref.read(currentUserProvider);
      if (user == null) throw Exception('Not authenticated');

      final service = ref.read(supabaseServiceProvider);

      final Uint8List bytes = await _receiptFile!.readAsBytes();
      final extension = _receiptFile!.name.split('.').last;
      final receiptPath = await service.uploadDepositReceipt(
        userId: user.id,
        bytes: bytes,
        fileExtension: extension,
      );

      await service.createDepositRequest(
        userId: user.id,
        amount: amount,
        depositChannel: _selectedBank!.providerName,
        receiptImagePath: receiptPath,
      );

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('تم إرسال الطلب'),
          content: const Text('سيتم مراجعة طلبك من قبل الإدارة المالية قريباً'),
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
      _showError('فشل إرسال طلب الشحن، حاول مرة أخرى');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bankAccountsAsync = ref.watch(bankAccountsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('شحن المحفظة'),
      ),
      body: SingleChildScrollView(
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
              'حساب الإيداع',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            bankAccountsAsync.when(
              data: (accounts) {
                if (accounts.isEmpty) {
                  return const Text(
                    'لا توجد حسابات إيداع متاحة حالياً، يرجى المحاولة لاحقاً',
                    style: TextStyle(color: AppTheme.textSecondary),
                  );
                }
                return Column(
                  children: accounts.map((bank) {
                    final isSelected = _selectedBank?.id == bank.id;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      color: isSelected
                          ? AppTheme.primary.withValues(alpha: 0.1)
                          : null,
                      child: ListTile(
                        leading: Icon(
                          Icons.account_balance,
                          color: isSelected
                              ? AppTheme.primary
                              : AppTheme.textSecondary,
                        ),
                        title: Text(bank.providerName),
                        subtitle: Text(
                          '${bank.accountHolderName} - ${bank.accountNumber}',
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle,
                                color: AppTheme.primary)
                            : null,
                        onTap: () => setState(() => _selectedBank = bank),
                      ),
                    );
                  }).toList(),
                );
              },
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (_, __) => const Text(
                'تعذّر تحميل حسابات الإيداع',
                style: TextStyle(color: AppTheme.error),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'إيصال التحويل',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickReceipt,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                height: 160,
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border),
                ),
                child: _receiptFile == null
                    ? const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_a_photo_outlined,
                              size: 40, color: AppTheme.textMuted),
                          SizedBox(height: 8),
                          Text('أرفق صورة الإيصال',
                              style: TextStyle(color: AppTheme.textSecondary)),
                        ],
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          File(_receiptFile!.path),
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: 160,
                        ),
                      ),
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
}
