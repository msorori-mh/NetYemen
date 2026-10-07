import '../domain/entities.dart';

abstract class WaselOneRepository {
  Future<List<FederatedAccessPlan>> getPublicPlans();

  Future<List<AccessEntitlement>> getMyEntitlements();

  Future<WaselOnePurchaseResult> purchasePlan({
    required String planId,
    required String idempotencyKey,
  });

  Future<RadiusAccessCredential> issueAccessCredential(String entitlementId);
}
