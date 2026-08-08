// lib/features/purchase/data/supabase_purchase_repository.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/utils/uuid_generator.dart';
import 'purchase_repository.dart';
import '../domain/entities.dart';

class SupabasePurchaseRepository implements PurchaseRepository {
  final SupabaseClient _client;

  const SupabasePurchaseRepository(this._client);

  @override
  Future<Map<String, dynamic>> purchasePackage({
    required String packageId,
  }) async {
    final result = await _client.rpc('purchase_package', params: {
      'p_package_id': packageId,
      'p_idempotency_key': UuidGenerator.generateV4(),
    });
    return result as Map<String, dynamic>;
  }

  @override
  Future<List<PurchaseOrder>> getMyPurchaseOrders() async {
    final result = await _client
        .from('purchase_records')
        .select('*, network_packages(name), networks(name)')
        .order('created_at', ascending: false);
    final list = result as List<dynamic>;
    return list.map((row) {
      final json = row as Map<String, dynamic>;
      return PurchaseOrder(
        id: json['id'] as String? ?? '',
        packageId: json['package_id'] as String? ?? '',
        networkId: json['network_id'] as String? ?? '',
        networkName: json['networks']?['name'] as String?,
        packageName: json['network_packages']?['name'] as String?,
        quantity: (json['units_purchased'] as num?)?.toInt() ?? 1,
        unitPrice: (json['amount_paid'] as num?)?.toInt() ?? 0,
        totalPrice: (json['amount_paid'] as num?)?.toInt() ?? 0,
        currency: json['currency'] as String? ?? 'YER',
        status: json['status'] as String? ?? 'completed',
        createdAt: json['created_at'] != null
            ? DateTime.parse(json['created_at'] as String)
            : null,
      );
    }).toList();
  }

  @override
  Future<List<FulfillmentRecord>> getMyFulfillmentRecords() async {
    // card_fulfillment_records RLS allows the purchase owner to see status
    // columns only; secret payload fields are never returned to the client.
    final result = await _client
        .from('card_fulfillment_records')
        .select('*, network_packages(name), networks(name)')
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
        networkName: json['networks']?['name'] as String?,
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
