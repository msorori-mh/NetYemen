// lib/features/purchase/presentation/purchase_detail_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/entities.dart';
import 'card_reveal_screen.dart';
import 'purchase_providers.dart';

class PurchaseDetailScreen extends ConsumerStatefulWidget {
  final String purchaseId;

  const PurchaseDetailScreen({super.key, required this.purchaseId});

  @override
  ConsumerState<PurchaseDetailScreen> createState() =>
      _PurchaseDetailScreenState();
}

class _PurchaseDetailScreenState extends ConsumerState<PurchaseDetailScreen> {
  bool _revealing = false;
  String? _message;

  @override
  Widget build(BuildContext context) {
    final purchaseAsync = ref.watch(purchaseDetailProvider(widget.purchaseId));

    return Scaffold(
      appBar: AppBar(title: const Text('تفاصيل المشتريات')),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: purchaseAsync.when(
          data: (purchase) => _buildContent(context, purchase),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('خطأ: $e')),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, PurchaseOrder? purchase) {
    if (purchase == null) {
      return const Center(child: Text('لم يتم العثور على عملية الشراء'));
    }

    final isCompleted = purchase.status == 'completed';

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ListView(
        children: [
          _InfoCard(purchase: purchase),
          const SizedBox(height: 16),
          if (isCompleted)
            ElevatedButton.icon(
              onPressed: _revealing
                  ? null
                  : () => _revealCard(context, purchase),
              icon: const Icon(Icons.visibility),
              label: _revealing
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('كشف الكرت'),
            ),
          const SizedBox(height: 12),
          if (_message != null)
            Text(
              _message!,
              style: TextStyle(
                color: _message!.startsWith('تم') ? Colors.green : Colors.red,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _revealCard(BuildContext context, PurchaseOrder purchase) async {
    setState(() {
      _revealing = true;
      _message = null;
    });

    try {
      final repo = ref.read(purchaseRepositoryProvider);
      final result = await repo.revealPurchaseCardSecret(purchase.id);
      if (context.mounted) {
        setState(() => _message = 'تم كشف الكرت');
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CardRevealScreen(
              revealedInfo: RevealedCardInfo(
                purchaseId: purchase.id,
                plaintext: result.ciphertextB64,
                disputeDeadline: result.disputeDeadline,
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _message = 'فشل الكشف: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _revealing = false);
      }
    }
  }
}

class _InfoCard extends StatelessWidget {
  final PurchaseOrder purchase;

  const _InfoCard({required this.purchase});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              purchase.packageName ?? 'باقة',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _row('الشبكة', purchase.networkName ?? '-'),
            _row('الحالة', _statusText(purchase.status)),
            _row('تاريخ الشراء', _formatDate(purchase.createdAt)),
            const Divider(height: 24),
            _row(
              'المبلغ الإجمالي',
              '${purchase.grossAmount} ${purchase.currency}',
            ),
            _row(
              'نسبة العمولة',
              '${(purchase.commissionRateSnapshot * 100).toStringAsFixed(2)}%',
            ),
            _row(
              'قيمة العمولة',
              '${purchase.commissionAmount} ${purchase.currency}',
            ),
            _row(
              'الصافي لصاحب الشبكة',
              '${purchase.ownerNetAmount} ${purchase.currency}',
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text('$label: ', style: const TextStyle(color: Colors.grey)),
          Expanded(child: Text(value)),
        ],
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

  String _formatDate(DateTime? date) {
    if (date == null) return '-';
    return '${date.day}/${date.month}/${date.year}';
  }
}
