// lib/screens/wallet/wallet_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/app_providers.dart';
import '../../utils/app_theme.dart';
import 'deposit_screen.dart';

class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userProfileProvider);
    final transactionsAsync = ref.watch(walletTransactionsProvider);

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
                userAsync.when(
                  data: (user) => Text(
                    '${user?.walletBalance ?? 0} ر.ي',
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
                      );
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

          // Transactions List
          Expanded(
            child: transactionsAsync.when(
              data: (transactions) {
                if (transactions.isEmpty) {
                  return const Center(
                    child: Text('لا توجد حركات حالياً'),
                  );
                }

                return ListView.builder(
                  itemCount: transactions.length,
                  itemBuilder: (context, index) {
                    final tx = transactions[index];
                    final isCredit =
                        tx['type'] == 'deposit' || tx['type'] == 'refund';
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
                      title: Text(tx['description'] ?? 'معاملة'),
                      subtitle: Text(tx['created_at']?.toString() ?? ''),
                      trailing: Text(
                        '${isCredit ? '+' : '-'}${tx['amount']} ر.ي',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: isCredit ? AppTheme.accent : AppTheme.error,
                        ),
                      ),
                    );
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
