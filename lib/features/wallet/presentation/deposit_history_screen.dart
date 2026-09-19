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
      appBar: AppBar(title: const Text('سجل الإيداعات')),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: depositsAsync.when(
          data: (deposits) {
            if (deposits.isEmpty) {
              return RefreshIndicator(
                onRefresh: () => _refresh(ref),
                child: const ListView(
                  physics: AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(height: 220),
                    Icon(Icons.receipt_long_outlined, size: 52),
                    SizedBox(height: 12),
                    Center(child: Text('لا توجد طلبات إيداع بعد')),
                  ],
                ),
              );
            }
            return RefreshIndicator(
              onRefresh: () => _refresh(ref),
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: deposits.length,
                itemBuilder: (context, index) {
                  final deposit = deposits[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: ListTile(
                      title: Text('${deposit.amount} ${deposit.currency}'),
                      subtitle: Text(
                        'المرجع: ${deposit.proofReference ?? '-'}'
                        '${deposit.createdAt == null ? '' : '\nالتاريخ: ${_formatDate(deposit.createdAt!)}'}'
                        '${deposit.reviewerNotes == null ? '' : '\nملاحظة المراجعة: ${deposit.reviewerNotes}'}',
                      ),
                      trailing: _DepositStatusBadge(status: deposit.status),
                    ),
                  );
                },
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('تعذر تحميل سجل الإيداعات'),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => ref.invalidate(depositHistoryProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(depositHistoryProvider);
    await ref.read(depositHistoryProvider.future);
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

class _DepositStatusBadge extends StatelessWidget {
  final String status;

  const _DepositStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'submitted' => ('مقدم', Colors.orange),
      'under_review' => ('قيد المراجعة', Colors.blue),
      'approved' => ('مقبول', Colors.green),
      'rejected' => ('مرفوض', Colors.red),
      'cancelled' => ('ملغي', Colors.grey),
      _ => (status, Colors.grey),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
