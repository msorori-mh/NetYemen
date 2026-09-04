// lib/screens/wallet/wallet_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/wallet_model.dart';
import '../../providers/app_providers.dart';
import '../../utils/app_theme.dart';
import 'deposit_screen.dart';

class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balanceAsync = ref.watch(walletBalanceProvider);
    final ledgerAsync = ref.watch(walletLedgerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('محفظتي'),
      ),
      body: Column(
        children: [
          // Balance Card
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'الرصيد المتاح',
                  style: TextStyle(fontSize: 14, color: Colors.white70),
                ),
                const SizedBox(height: 8),
                balanceAsync.when(
                  data: (balance) => Text(
                    '$balance ر.ي',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  loading: () =>
                      const CircularProgressIndicator(color: Colors.white),
                  error: (_, __) =>
                      const Text('---', style: TextStyle(color: Colors.white)),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const DepositScreen()),
                      ).then((_) {
                        ref.invalidate(walletBalanceProvider);
                        ref.invalidate(walletLedgerProvider);
                      });
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('شحن الرصيد'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppTheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Ledger (wallet_ledger_entries — the immutable movement log)
          Expanded(
            child: ledgerAsync.when(
              data: (entries) {
                if (entries.isEmpty) {
                  return const Center(
                    child: Text('لا توجد حركات حالياً'),
                  );
                }

                return ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return _LedgerEntryTile(entry: entry);
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => const Center(child: Text('حدث خطأ')),
            ),
          ),
        ],
      ),
    );
  }
}

class _LedgerEntryTile extends StatelessWidget {
  final WalletLedgerEntry entry;

  const _LedgerEntryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final isCredit = entry.isCredit;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: isCredit
            ? AppTheme.accent.withValues(alpha: 0.1)
            : AppTheme.error.withValues(alpha: 0.1),
        child: Icon(
          isCredit ? Icons.arrow_downward : Icons.arrow_upward,
          color: isCredit ? AppTheme.accent : AppTheme.error,
        ),
      ),
      title: Text(entry.referenceLabel),
      subtitle: Text(
        '${entry.createdAt.day}/${entry.createdAt.month}/${entry.createdAt.year}',
      ),
      trailing: Text(
        '${isCredit ? '+' : '-'}${entry.amount} ر.ي',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: isCredit ? AppTheme.accent : AppTheme.error,
        ),
      ),
    );
  }
}
