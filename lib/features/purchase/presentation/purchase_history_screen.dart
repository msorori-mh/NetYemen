// lib/features/purchase/presentation/purchase_history_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'purchase_providers.dart';

class PurchaseHistoryScreen extends ConsumerWidget {
  const PurchaseHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final purchasesAsync = ref.watch(purchaseHistoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('سجل المشتريات'),
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: purchasesAsync.when(
          data: (purchases) {
            if (purchases.isEmpty) {
              return const Center(child: Text('لا توجد مشتريات'));
            }
            return ListView.builder(
              itemCount: purchases.length,
              itemBuilder: (context, index) {
                final purchase = purchases[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    title: Text(purchase.packageName ?? 'باقة'),
                    subtitle: Text(
                      'الشبكة: ${purchase.networkName ?? '-'}\n'
                      'السعر: ${purchase.totalPrice} ${purchase.currency}\n'
                      'الحالة: ${_statusText(purchase.status)}',
                    ),
                    trailing: Text(
                      purchase.createdAt != null
                          ? '${purchase.createdAt!.day}/${purchase.createdAt!.month}'
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
      case 'completed':
        return 'مكتمل';
      case 'refunded':
        return 'مسترجع';
      case 'disputed':
        return 'متنازع عليه';
      case 'cancelled':
        return 'ملغي';
      default:
        return status;
    }
  }
}
