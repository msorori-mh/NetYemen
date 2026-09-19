// lib/features/purchase/presentation/purchase_confirmation_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../packages/domain/entities.dart';
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
                'السعر: ${package.price} ${package.currency}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (submission.hasError) ...[
                Text(
                  _purchaseErrorText(submission.error!),
                  key: const Key('purchase-submit-error'),
                  style: const TextStyle(color: Colors.red),
                ),
                const SizedBox(height: 12),
              ],
              ElevatedButton(
                onPressed: submission.isLoading
                    ? null
                    : () => _confirmPurchase(context, ref),
                child: submission.isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        submission.hasError
                            ? 'إعادة المحاولة بأمان'
                            : 'تأكيد الشراء',
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmPurchase(BuildContext context, WidgetRef ref) async {
    try {
      final result = await ref
          .read(purchaseSubmissionProvider.notifier)
          .submit(package.id);

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

  String _purchaseErrorText(Object error) {
    final message = error.toString();
    if (message.contains('INSUFFICIENT_BALANCE')) {
      return 'رصيد المحفظة غير كافٍ لإتمام الشراء.';
    }
    if (message.contains('OUT_OF_STOCK')) {
      return 'نفدت كروت هذه الباقة حاليًا. اختر باقة أخرى أو حاول لاحقًا.';
    }
    if (message.contains('PACKAGE_UNAVAILABLE') ||
        message.contains('NETWORK_UNAVAILABLE')) {
      return 'الباقة أو الشبكة غير متاحة حاليًا.';
    }
    if (message.contains('UNAUTHENTICATED')) {
      return 'انتهت جلسة الدخول. سجّل الدخول ثم حاول مجددًا.';
    }
    return 'تعذر تأكيد نتيجة العملية. أعد المحاولة بأمان؛ لن يتم الخصم مرتين.';
  }
}
