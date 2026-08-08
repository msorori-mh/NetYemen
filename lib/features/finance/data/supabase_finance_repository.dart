// lib/features/finance/data/supabase_finance_repository.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import 'finance_repository.dart';

class SupabaseFinanceRepository implements FinanceRepository {
  final SupabaseClient _client;

  const SupabaseFinanceRepository(this._client);

  @override
  Future<List<Map<String, dynamic>>> getDepositQueue(String? status) async {
    final result = await _client.rpc('get_finance_deposit_queue', params: {
      'p_status': status,
    });
    return (result as List<dynamic>)
        .map((row) => row as Map<String, dynamic>)
        .toList();
  }

  @override
  Future<void> reviewDeposit(String id, String action, {String? notes}) async {
    await _client.rpc(
      'review_wallet_deposit_request',
      params: {
        'p_deposit_id': id,
        'p_action': action,
        'p_rejection_reason': notes,
      },
    );
  }
}
