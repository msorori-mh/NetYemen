// lib/features/purchase/presentation/purchase_history_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/app_providers.dart';
import '../../../screens/auth/login_screen.dart';
import '../../network_discovery/presentation/networks_list_screen.dart';
import 'purchase_detail_screen.dart';
import 'purchase_providers.dart';

class PurchaseHistoryScreen extends ConsumerWidget {
  const PurchaseHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final user = ref.watch(currentUserProvider);
    if (user == null && !config.isDemoMode) {
      return Scaffold(
        appBar: AppBar(title: const Text('سجل المشتريات')),
        body: Directionality(
          textDirection: TextDirection.rtl,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 56),
                  const SizedBox(height: 16),
                  const Text(
                    'يرجى تسجيل الدخول لعرض سجل المشتريات',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    ),
                    icon: const Icon(Icons.login),
                    label: const Text('تسجيل الدخول'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final purchasesAsync = ref.watch(purchaseHistoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('سجل المشتريات')),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: purchasesAsync.when(
          data: (purchases) {
            if (purchases.isEmpty) {
              return RefreshIndicator(
                onRefresh: () => _refresh(ref),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    const SizedBox(height: 150),
                    const Icon(Icons.shopping_bag_outlined, size: 56),
                    const SizedBox(height: 12),
                    const Center(child: Text('لا توجد مشتريات بعد')),
                    const SizedBox(height: 12),
                    Center(
                      child: FilledButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const NetworksListScreen(),
                          ),
                        ),
                        icon: const Icon(Icons.wifi),
                        label: const Text('استكشاف الشبكات والباقات'),
                      ),
                    ),
                  ],
                ),
              );
            }
            return RefreshIndicator(
              onRefresh: () => _refresh(ref),
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: purchases.length,
                itemBuilder: (context, index) {
                  final purchase = purchases[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: ListTile(
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(purchase.packageName ?? 'باقة إنترنت'),
                          ),
                          _PurchaseStatusBadge(status: purchase.status),
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '${purchase.networkName ?? 'شبكة'}\n'
                          '${purchase.totalPrice} ${purchase.currency}'
                          '${purchase.createdAt == null ? '' : ' · ${_formatDate(purchase.createdAt!)}'}',
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_left),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              PurchaseDetailScreen(purchaseId: purchase.id),
                        ),
                      ),
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
                const Text('تعذر تحميل سجل المشتريات'),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => ref.invalidate(purchaseHistoryProvider),
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
    ref.invalidate(purchaseHistoryProvider);
    await ref.read(purchaseHistoryProvider.future);
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

class _PurchaseStatusBadge extends StatelessWidget {
  final String status;

  const _PurchaseStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'completed' => ('مكتمل', Colors.green),
      'refunded' => ('مسترجع', Colors.blue),
      'disputed' => ('قيد النزاع', Colors.orange),
      'cancelled' => ('ملغي', Colors.grey),
      _ => ('قيد المعالجة', Colors.orange),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
