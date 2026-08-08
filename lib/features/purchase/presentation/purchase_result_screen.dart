// lib/features/purchase/presentation/purchase_result_screen.dart

import 'package:flutter/material.dart';

class PurchaseResultScreen extends StatelessWidget {
  final bool success;
  final Map<String, dynamic>? purchaseResult;
  final String? errorMessage;
  final String packageName;

  const PurchaseResultScreen({
    super.key,
    required this.success,
    this.purchaseResult,
    this.errorMessage,
    required this.packageName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('نتيجة الشراء'),
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                success ? Icons.check_circle : Icons.error,
                color: success ? Colors.green : Colors.red,
                size: 64,
              ),
              const SizedBox(height: 16),
              Text(
                success ? 'تم الشراء بنجاح' : 'فشل الشراء',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text('الباقة: $packageName'),
              if (success && purchaseResult != null) ...[
                Text(
                    'السعر الإجمالي: ${purchaseResult!['amount_paid'] ?? purchaseResult!['total_price']} YER'),
                Text(
                    'حالة التسليم: ${_fulfillmentText(purchaseResult!['status'] as String?)}'),
                const SizedBox(height: 16),
                const Text(
                  'التسليم الخارجي غير مربوط في النسخة التجريبية. لا توجد بيانات كرت سرية، ولن يظهر نجاح تسليم وهمي حتى اعتماد OD-CARD-01.',
                  style: TextStyle(color: Colors.orange),
                ),
              ],
              if (!success && errorMessage != null)
                Text('السبب: $errorMessage',
                    style: const TextStyle(color: Colors.red)),
              const Spacer(),
              ElevatedButton(
                onPressed: () =>
                    Navigator.of(context).popUntil((route) => route.isFirst),
                child: const Text('العودة للرئيسية'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fulfillmentText(String? status) {
    switch (status) {
      case 'completed':
        return 'بانتظار مزود تسليم آمن — غير مربوط';
      case 'pending_secret':
        return 'بانتظار إعداد بيانات الكرت الآمنة';
      case 'fulfilled':
        return 'تم التسليم';
      default:
        return status ?? 'غير معروف';
    }
  }
}
