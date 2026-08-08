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

  @override
  Future<List<Map<String, dynamic>>> getActivePaymentDestinations() async {
    final result = await _client.rpc('get_active_payment_destinations');
    return (result as List<dynamic>)
        .map((row) => row as Map<String, dynamic>)
        .toList();
  }

  @override
  Future<Map<String, dynamic>> createPaymentDestination({
    required String providerType,
    required String displayName,
    String? accountHolderName,
    String? accountIdentifier,
    String? instructions,
    String currency = 'YER',
    int sortOrder = 0,
  }) async {
    final result = await _client.rpc(
      'admin_create_payment_destination',
      params: {
        'p_provider_type': providerType,
        'p_display_name': displayName,
        'p_account_holder_name': accountHolderName,
        'p_account_identifier': accountIdentifier,
        'p_instructions': instructions,
        'p_currency': currency,
        'p_sort_order': sortOrder,
      },
    );
    return result as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>> updatePaymentDestination(
    String id, {
    String? providerType,
    String? displayName,
    String? accountHolderName,
    String? accountIdentifier,
    String? instructions,
    String? currency,
    int? sortOrder,
  }) async {
    final result = await _client.rpc(
      'admin_update_payment_destination',
      params: {
        'p_id': id,
        'p_provider_type': providerType,
        'p_display_name': displayName,
        'p_account_holder_name': accountHolderName,
        'p_account_identifier': accountIdentifier,
        'p_instructions': instructions,
        'p_currency': currency,
        'p_sort_order': sortOrder,
      },
    );
    return result as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>> setPaymentDestinationActive(String id, bool active) async {
    final result = await _client.rpc(
      'admin_set_payment_destination_active',
      params: {'p_id': id, 'p_active': active},
    );
    return result as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>> reorderPaymentDestinations(List<String> orderedIds) async {
    final result = await _client.rpc(
      'admin_reorder_payment_destinations',
      params: {'p_ordered_ids': orderedIds},
    );
    return result as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>> createSettlementBatch({
    required DateTime periodStart,
    required DateTime periodEnd,
    String? networkId,
  }) async {
    final result = await _client.rpc(
      'finance_create_settlement_batch',
      params: {
        'p_period_start': periodStart.toIso8601String().substring(0, 10),
        'p_period_end': periodEnd.toIso8601String().substring(0, 10),
        'p_network_id': networkId,
      },
    );
    return result as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>> approveSettlementBatch(String batchId) async {
    final result = await _client.rpc(
      'finance_approve_settlement_batch',
      params: {'p_batch_id': batchId},
    );
    return result as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>> markSettlementPaid(String batchId, {String? notes}) async {
    final result = await _client.rpc(
      'finance_mark_settlement_paid',
      params: {'p_batch_id': batchId, 'p_notes': notes},
    );
    return result as Map<String, dynamic>;
  }

  @override
  Future<List<Map<String, dynamic>>> getFinanceSettlementBatches(String? status) async {
    final result = await _client.rpc(
      'get_finance_settlement_batches',
      params: {'p_status': status},
    );
    return (result as List<dynamic>)
        .map((row) => row as Map<String, dynamic>)
        .toList();
  }

  @override
  Future<List<Map<String, dynamic>>> getOwnerSettlements(String? networkId) async {
    final result = await _client.rpc(
      'get_owner_settlements',
      params: {'p_network_id': networkId},
    );
    return (result as List<dynamic>)
        .map((row) => row as Map<String, dynamic>)
        .toList();
  }
}
