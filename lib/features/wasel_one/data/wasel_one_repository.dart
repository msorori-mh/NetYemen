import '../domain/entities.dart';

abstract class WaselOneRepository {
  Future<List<FederatedAccessPlan>> getPublicPlans();

  Future<List<AccessEntitlement>> getMyEntitlements();

  Future<RadiusAccessCredential> issueAccessCredential(String entitlementId);
}
