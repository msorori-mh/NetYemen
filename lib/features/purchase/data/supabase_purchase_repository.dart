// lib/features/purchase/data/supabase_purchase_repository.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import 'purchase_repository.dart';
import '../domain/entities.dart';

class SupabasePurchaseRepository implements PurchaseRepository {
  final SupabaseClient _client;

  const SupabasePurchaseRepository(this._client);

  @override
  Future<Map<String, dynamic>> purchasePackage({
    required String packageId,
    required String idempotencyKey,
  }) async {
    final result = await _client.rpc(
      'purchase_package',
      params: {
        'p_package_id': packageId,
        'p_idempotency_key': idempotencyKey,
      },
    );
    return result as Map<String, dynamic>;
  }

  @override
  Future<List<PurchaseOrder>> getMyPurchaseOrders() async {
    final result = await _client
        .from('purchase_records')
        .select('*, network_packages(name), networks(commercial_name)')
        .order('created_at', ascending: false);
    final list = result as List<dynamic>;
    return list.map((row) {
      final json = row as Map<String, dynamic>;
      return PurchaseOrder.fromJson(json);
    }).toList();
  }

  @override
  Future<CardRevealResult> revealPurchaseCardSecret(String purchaseId) async {
    final response = await _client.functions.invoke(
      'notification-transport-adapter',
      body: {
        'action': 'reveal_card_secret',
        'purchase_id': purchaseId,
      },
    );
    final data = response.data;
    if (response.status < 200 || response.status >= 300 || data is! Map) {
      throw StateError('CARD_REVEAL_FAILED');
    }

    final result = Map<String, dynamic>.from(data);
    final plaintext = result['plaintext'] as String?;
    if (plaintext == null || plaintext.trim().isEmpty) {
      throw StateError(
        result['error'] as String? ?? 'CARD_REVEAL_EMPTY_RESPONSE',
      );
    }
    return CardRevealResult.fromJson(result);
  }

  @override
  Future<void> submitInvalidCardDispute(
    String purchaseId,
    String reason,
  ) async {
    await _client.rpc(
      'submit_invalid_card_dispute',
      params: {'p_purchase_id': purchaseId, 'p_reason': reason},
    );
  }

  @override
  Future<List<FulfillmentRecord>> getMyFulfillmentRecords() async {
    // card_fulfillment_records RLS allows the purchase owner to see status
    // columns only; secret payload fields are never returned to the client.
    final result = await _client
        .from('card_fulfillment_records')
        .select('*, network_packages(name), networks(commercial_name)')
        .order('created_at', ascending: false);
    final list = result as List<dynamic>;
    return list.map((row) {
      final json = row as Map<String, dynamic>;
      return FulfillmentRecord(
        id: json['id'] as String? ?? '',
        purchaseOrderId: json['purchase_id'] as String? ?? '',
        packageId: json['package_id'] as String? ?? '',
        networkId: json['network_id'] as String? ?? '',
        packageName: json['network_packages']?['name'] as String?,
        networkName: json['networks']?['commercial_name'] as String?,
        status: json['status'] as String? ?? 'pending',
        disputeWindowEndsAt: json['dispute_window_ends_at'] != null
            ? DateTime.parse(json['dispute_window_ends_at'] as String)
            : null,
        createdAt: json['created_at'] != null
            ? DateTime.parse(json['created_at'] as String)
            : null,
      );
    }).toList();
  }
}
