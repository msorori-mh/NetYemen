// lib/features/wallet/data/supabase_wallet_repository.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import 'wallet_repository.dart';
import '../domain/entities.dart';

class SupabaseWalletRepository implements WalletRepository {
  final SupabaseClient _client;
  final String? Function()? _currentUserId;

  /// [currentUserId] overrides the signed-in user lookup (tests only).
  const SupabaseWalletRepository(
    this._client, {
    String? Function()? currentUserId,
  }) : _currentUserId = currentUserId;

  String? get _userId => _currentUserId?.call() ?? _client.auth.currentUser?.id;

  @override
  Future<WalletSummary> getMyWalletSummary() async {
    final result = await _client.rpc('get_customer_wallet');
    return WalletSummary.fromJson(result as Map<String, dynamic>);
  }

  @override
  Future<List<DepositRequest>> getMyDepositRequests() async {
    // RLS also lets finance/admin read other customers' deposits, so "my
    // deposits" must filter by the signed-in user explicitly.
    final userId = _userId;
    if (userId == null) return const [];
    final result = await _client
        .from('wallet_deposit_requests')
        .select()
        .eq('user_id', userId)
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
    required String idempotencyKey,
    String? paymentDestinationId,
    String? proofReference,
  }) async {
    final result = await _client.rpc(
      'create_wallet_deposit_request',
      params: {
        'p_amount': amount,
        // The server rejects an empty reference with INVALID_REFERENCE; the
        // deposit form requires it. No proof file upload exists yet, so the
        // storage path stays null rather than echoing the reference.
        'p_reference_number': proofReference ?? '',
        'p_payment_destination_id': paymentDestinationId,
        'p_proof_storage_path': null,
        'p_idempotency_key': idempotencyKey,
      },
    );
    return (result as Map<String, dynamic>)['id'] as String;
  }
}
