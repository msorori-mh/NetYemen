// lib/screens/wallet/bank_directory_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/wallet_model.dart';
import '../../providers/app_providers.dart';
import '../../utils/app_theme.dart';

class BankDirectoryScreen extends ConsumerWidget {
  const BankDirectoryScreen({super.key});

  void _copy(BuildContext context, String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم نسخ $label')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bankAccountsAsync = ref.watch(bankAccountsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('دليل حسابات الإيداع')),
      body: bankAccountsAsync.when(
        data: (accounts) {
          if (accounts.isEmpty) {
            return const Center(
              child: Text('لا توجد حسابات إيداع متاحة حالياً'),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: accounts.length,
            itemBuilder: (context, index) {
              final bank = accounts[index];
              return _BankAccountCard(
                bank: bank,
                onCopyAccountNumber: () =>
                    _copy(context, 'رقم الحساب', bank.accountNumber),
                onCopyHolderName: () =>
                    _copy(context, 'اسم صاحب الحساب', bank.accountHolderName),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('تعذّر تحميل الدليل')),
      ),
    );
  }
}

class _BankAccountCard extends StatelessWidget {
  final BankAccount bank;
  final VoidCallback onCopyAccountNumber;
  final VoidCallback onCopyHolderName;

  const _BankAccountCard({
    required this.bank,
    required this.onCopyAccountNumber,
    required this.onCopyHolderName,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.account_balance, color: AppTheme.primary),
                const SizedBox(width: 8),
                Text(
                  bank.providerName,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            if (bank.branch != null) ...[
              const SizedBox(height: 4),
              Text(bank.branch!, style: const TextStyle(color: AppTheme.textSecondary)),
            ],
            const Divider(height: 20),
            _CopyableRow(
              label: 'اسم صاحب الحساب',
              value: bank.accountHolderName,
              onCopy: onCopyHolderName,
            ),
            const SizedBox(height: 8),
            _CopyableRow(
              label: 'رقم الحساب',
              value: bank.accountNumber,
              onCopy: onCopyAccountNumber,
            ),
            if (bank.notes != null) ...[
              const SizedBox(height: 8),
              Text(
                bank.notes!,
                style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CopyableRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onCopy;

  const _CopyableRow({
    required this.label,
    required this.value,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        IconButton(
          onPressed: onCopy,
          icon: const Icon(Icons.copy, size: 20),
          color: AppTheme.primary,
        ),
      ],
    );
  }
}
