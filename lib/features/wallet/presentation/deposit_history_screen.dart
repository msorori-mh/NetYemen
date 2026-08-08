// lib/features/wallet/presentation/deposit_history_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'wallet_providers.dart';

class DepositHistoryScreen extends ConsumerWidget {
  const DepositHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final depositsAsync = ref.watch(depositHistoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('سجل الإيداعات'),
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: depositsAsync.when(
          data: (deposits) {
            if (deposits.isEmpty) {
              return const Center(child: Text('لا توجد إيداعات'));
            }
            return ListView.builder(
              itemCount: deposits.length,
              itemBuilder: (context, index) {
                final deposit = deposits[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    title: Text('${deposit.amount} ${deposit.currency}'),
                    subtitle: Text(
                      'الحالة: ${_statusText(deposit.status)}\n'
                      'المرجع: ${deposit.proofReference ?? '-'}',
                    ),
                    trailing: Text(
                      deposit.createdAt != null
                          ? '${deposit.createdAt!.day}/${deposit.createdAt!.month}'
                          : '',
                    ),
                  ),
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('خطأ: $e')),
        ),
      ),
    );
  }

  String _statusText(String status) {
    switch (status) {
      case 'submitted':
        return 'مقدم';
      case 'under_review':
        return 'قيد المراجعة';
      case 'approved':
        return 'مقبول';
      case 'rejected':
        return 'مرفوض';
      case 'cancelled':
        return 'ملغي';
      default:
        return status;
    }
  }
}
