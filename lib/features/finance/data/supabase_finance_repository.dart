// lib/features/finance/data/supabase_finance_repository.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import 'finance_repository.dart';

class SupabaseFinanceRepository implements FinanceRepository {
  final SupabaseClient _client;

  const SupabaseFinanceRepository(this._client);

  @override
  Future<List<Map<String, dynamic>>> getActivePaymentDestinations() async {
    final result = await _client.rpc('get_active_payment_destinations');
    return (result as List<dynamic>)
        .map((row) => row as Map<String, dynamic>)
        .toList();
  }
}
