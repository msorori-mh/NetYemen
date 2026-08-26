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
              ElevatedButton(
                onPressed: () => _confirmPurchase(context, ref),
                child: const Text('تأكيد الشراء'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmPurchase(BuildContext context, WidgetRef ref) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final repo = ref.read(purchaseRepositoryProvider);
      final result = await repo.purchasePackage(packageId: package.id);

      if (context.mounted) {
        Navigator.of(context).pop();
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
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => PurchaseResultScreen(
              success: false,
              errorMessage: e.toString(),
              packageName: package.name,
            ),
          ),
        );
      }
    }
  }
}
