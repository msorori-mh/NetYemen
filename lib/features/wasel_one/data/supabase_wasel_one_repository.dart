import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/entities.dart';
import 'wasel_one_repository.dart';

class SupabaseWaselOneRepository implements WaselOneRepository {
  final SupabaseClient _client;

  const SupabaseWaselOneRepository(this._client);

  @override
  Future<List<FederatedAccessPlan>> getPublicPlans() async {
    final response = await _client
        .from('federated_access_plans')
        .select('*, federated_plan_networks(count)')
        .eq('status', 'active')
        .eq('is_public', true)
        .order('retail_price');
    return (response as List<dynamic>)
        .map(
          (row) => FederatedAccessPlan.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList();
  }

  @override
  Future<List<AccessEntitlement>> getMyEntitlements() async {
    final response = await _client
        .from('access_entitlements')
        .select('*, federated_access_plans(name)')
        .order('created_at', ascending: false);
    return (response as List<dynamic>)
        .map(
          (row) =>
              AccessEntitlement.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  @override
  Future<WaselOnePurchaseResult> purchasePlan({
    required String planId,
    required String idempotencyKey,
  }) async {
    final response = await _client.rpc(
      'purchase_federated_access_plan',
      params: {
        'p_plan_id': planId,
        'p_idempotency_key': idempotencyKey,
      },
    );
    if (response is! Map) throw StateError('INVALID_PURCHASE_RESPONSE');
    final result = WaselOnePurchaseResult.fromJson(
      Map<String, dynamic>.from(response),
    );
    if (!result.isCompleted ||
        result.purchaseId.isEmpty ||
        result.entitlementId.isEmpty) {
      throw StateError('INVALID_PURCHASE_RESPONSE');
    }
    return result;
  }

  @override
  Future<RadiusAccessCredential> issueAccessCredential(
    String entitlementId,
  ) async {
    final response = await _client.rpc(
      'issue_radius_access_credential',
      params: {'p_entitlement_id': entitlementId},
    );
    if (response is! Map) throw StateError('INVALID_CREDENTIAL_RESPONSE');
    return RadiusAccessCredential.fromJson(Map<String, dynamic>.from(response));
  }
}
