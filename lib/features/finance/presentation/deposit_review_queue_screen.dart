// lib/features/finance/presentation/deposit_review_queue_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'finance_providers.dart';
import 'deposit_detail_screen.dart';

class DepositReviewQueueScreen extends ConsumerWidget {
  const DepositReviewQueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queueAsync = ref.watch(depositQueueProvider(null));

    return Scaffold(
      appBar: AppBar(title: const Text('قبول الإيداعات')),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: queueAsync.when(
          data: (deposits) {
            if (deposits.isEmpty) {
              return const Center(child: Text('لا توجد طلبات إيداع'));
            }
            return ListView.builder(
              itemCount: deposits.length,
              itemBuilder: (context, index) {
                final deposit = deposits[index];
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: ListTile(
                    title: Text('${deposit['amount']} ${deposit['currency']}'),
                    subtitle: Text(
                      'الحالة: ${_statusText(deposit['status'] as String)}\n'
                      'المرجع: ${deposit['proof_reference'] ?? '-'}',
                    ),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => DepositDetailScreen(deposit: deposit),
                      ),
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
      default:
        return status;
    }
  }
}
