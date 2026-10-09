// lib/features/purchase/presentation/purchase_confirmation_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../packages/domain/entities.dart';
import '../../security/presentation/pin_confirmation.dart';
import '../../wallet/presentation/wallet_providers.dart';
import 'purchase_providers.dart';
import 'purchase_result_screen.dart';

class PurchaseConfirmationScreen extends ConsumerWidget {
  final NetworkPackage package;
  final String networkName;

  const PurchaseConfirmationScreen({
    super.key,
    required this.package,
    required this.networkName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final submission = ref.watch(purchaseSubmissionProvider);
    final notifier = ref.watch(purchaseSubmissionProvider.notifier);
    // The submission notifier is shared: only surface an error that belongs
    // to this package at this price, never one left by another purchase.
    final isThisPurchase = notifier.describes(
      packageId: package.id,
      expectedPrice: package.price,
    );
    final showsError =
        isThisPurchase && submission.hasError && !submission.isLoading;
    final Object? error = showsError ? submission.error : null;
    final priceChanged = error != null && isPriceChangedError(error);
    final label = error != null ? 'إعادة المحاولة بأمان' : 'تأكيد الشراء';

    return Scaffold(
      appBar: AppBar(title: const Text('تأكيد الشراء')),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                package.name,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text('الشبكة: $networkName'),
              const SizedBox(height: 16),
              Text(
                'السعر: ${package.displayPrice}',
                key: const Key('purchase-confirmation-price'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'سيُخصم هذا المبلغ من رصيد محفظتك عند التأكيد.',
                style: TextStyle(color: Colors.grey),
              ),
              const Spacer(),
              if (error != null) ...[
                Text(
                  purchaseErrorMessage(error),
                  key: const Key('purchase-submit-error'),
                  style: const TextStyle(color: Colors.red),
                ),
                const SizedBox(height: 12),
              ],
              if (priceChanged)
                ElevatedButton(
                  key: const Key('purchase-price-changed-back'),
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('العودة إلى الباقات'),
                )
              else
                ElevatedButton(
                  key: const Key('purchase-confirm'),
                  onPressed: submission.isLoading
                      ? null
                      : () => _confirmPurchase(context, ref),
                  child: submission.isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(label),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmPurchase(BuildContext context, WidgetRef ref) async {
    // The server refuses a purchase until the PIN was verified recently.
    if (!await confirmAccountPin(context, ref) || !context.mounted) return;
    try {
      final result = await ref
          .read(purchaseSubmissionProvider.notifier)
          .submit(package.id, expectedPrice: package.price);

      if (context.mounted) {
        ref.invalidate(purchaseHistoryProvider);
        ref.invalidate(fulfillmentRecordsProvider);
        ref.invalidate(walletSummaryProvider);
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => PurchaseResultScreen(
              success: true,
              purchaseResult: result,
              packageName: package.name,
            ),
          ),
        );
      }
    } catch (_) {
      // The provider retains the idempotency key and exposes the error inline.
      // Retrying this logical purchase cannot create a second debit/order.
    }
  }
}
