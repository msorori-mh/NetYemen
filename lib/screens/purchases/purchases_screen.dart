// lib/screens/purchases/purchases_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import '../../models/purchase_model.dart';
import '../../providers/app_providers.dart';
import '../../utils/app_theme.dart';

class PurchasesScreen extends ConsumerWidget {
  const PurchasesScreen({super.key});

  void _revealCard(BuildContext context, Purchase purchase) {
    showDialog(
      context: context,
      builder: (_) => _RevealCardDialog(purchase: purchase),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final purchasesAsync = ref.watch(userPurchasesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('مشترياتي'),
      ),
      body: purchasesAsync.when(
        data: (purchases) {
          if (purchases.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 64,
                    color: AppTheme.textMuted,
                  ),
                  SizedBox(height: 16),
                  Text('لا توجد مشتريات حالياً'),
                  SizedBox(height: 8),
                  Text(
                    'ابدأ بشراء كرت من شبكة متاحة',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: purchases.length,
            itemBuilder: (context, index) {
              final purchase = purchases[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor:
                                AppTheme.primary.withValues(alpha: 0.1),
                            child: Text(
                              purchase.networkName?.isNotEmpty == true
                                  ? purchase.networkName![0]
                                  : '?',
                              style: const TextStyle(
                                color: AppTheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  purchase.networkName ?? 'شبكة غير معروفة',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  purchase.formattedDate,
                                  style: const TextStyle(
                                      color: AppTheme.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${purchase.pricePaid} ر.ي',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primary,
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => _revealCard(context, purchase),
                          icon: const Icon(Icons.visibility_outlined),
                          label: const Text('عرض رقم الكرت'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('حدث خطأ')),
      ),
    );
  }
}

/// COND-6: only the purchaser can reveal their own card. The plaintext is
/// fetched fresh on every open and never stored in provider state — it lives
/// only in this dialog's local State for as long as it's on screen.
class _RevealCardDialog extends ConsumerStatefulWidget {
  final Purchase purchase;

  const _RevealCardDialog({required this.purchase});

  @override
  ConsumerState<_RevealCardDialog> createState() => _RevealCardDialogState();
}

class _RevealCardDialogState extends ConsumerState<_RevealCardDialog> {
  String? _cardNumber;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reveal();
  }

  Future<void> _reveal() async {
    try {
      final service = ref.read(supabaseServiceProvider);
      final cardNumber =
          await service.revealPurchasedCard(widget.purchase.id);
      if (mounted) setState(() => _cardNumber = cardNumber);
    } catch (e) {
      if (mounted) setState(() => _error = 'تعذّر جلب رقم الكرت');
    }
  }

  void _copyToClipboard() {
    if (_cardNumber == null) return;
    Clipboard.setData(ClipboardData(text: _cardNumber!));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم نسخ الرقم')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('رقم الكرت'),
      content: _error != null
          ? Text(_error!, style: const TextStyle(color: AppTheme.error))
          : _cardNumber == null
              ? const SizedBox(
                  height: 60,
                  child: Center(child: CircularProgressIndicator()),
                )
              : SelectableText(
                  _cardNumber!,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                  textAlign: TextAlign.center,
                ),
      actions: [
        if (_cardNumber != null)
          TextButton.icon(
            onPressed: _copyToClipboard,
            icon: const Icon(Icons.copy),
            label: const Text('نسخ'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إغلاق'),
        ),
      ],
    );
  }
}
