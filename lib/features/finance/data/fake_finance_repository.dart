// lib/features/finance/data/fake_finance_repository.dart

import 'finance_repository.dart';

class FakeFinanceRepository implements FinanceRepository {
  final List<Map<String, dynamic>> _paymentDestinations = [
    {
      'id': 'fake-dest-1',
      'provider_type': 'bank_account',
      'display_name': 'بنك الكريمي (تجريبي)',
      'account_holder_name': 'WASEL NET Demo',
      'account_identifier': 'DEMO-123456',
      'instructions': 'Transfer to demo account',
      'currency': 'YER',
      'sort_order': 0,
      'is_active': true,
    },
  ];

  @override
  Future<List<Map<String, dynamic>>> getActivePaymentDestinations() async {
    await Future.delayed(const Duration(milliseconds: 100));
    return List.unmodifiable(
      _paymentDestinations.where((d) => d['is_active'] == true),
    );
  }
}
