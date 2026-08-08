// lib/features/wallet/data/supabase_wallet_repository.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/utils/uuid_generator.dart';
import 'wallet_repository.dart';
import '../domain/entities.dart';

class SupabaseWalletRepository implements WalletRepository {
  final SupabaseClient _client;

  const SupabaseWalletRepository(this._client);

  @override
  Future<WalletSummary> getMyWalletSummary() async {
    final result = await _client.rpc('get_customer_wallet');
    return WalletSummary.fromJson(result as Map<String, dynamic>);
  }

  @override
  Future<List<DepositRequest>> getMyDepositRequests() async {
    final result = await _client
        .from('wallet_deposit_requests')
        .select()
        .order('created_at', ascending: false);
    final list = result as List<dynamic>;
    return list
        .map((row) => DepositRequest.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<DepositChannel>> getActiveDepositChannels() async {
    final result = await _client
        .from('payment_destinations')
        .select()
        .eq('is_active', true)
        .order('sort_order');
    final list = result as List<dynamic>;
    return list
        .map((row) => DepositChannel.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<String> createDepositRequest({
    required int amount,
    String? paymentDestinationId,
    String? proofReference,
  }) async {
    final result = await _client.rpc(
      'create_wallet_deposit_request',
      params: {
        'p_amount': amount,
        'p_reference_number': proofReference ?? '',
        'p_payment_destination_id': paymentDestinationId,
        'p_proof_storage_path': proofReference,
        'p_idempotency_key': UuidGenerator.generateV4(),
      },
    );
    return (result as Map<String, dynamic>)['id'] as String;
  }
}
