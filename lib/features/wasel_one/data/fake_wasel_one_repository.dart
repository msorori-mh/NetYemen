import '../../../core/demo/demo_wallet_store.dart';
import 'wasel_one_repository.dart';
import '../domain/entities.dart';

class FakeWaselOneRepository implements WaselOneRepository {
  static final _now = DateTime.now();

  final DemoWalletStore _walletStore;

  FakeWaselOneRepository([DemoWalletStore? walletStore])
      : _walletStore = walletStore ?? DemoWalletStore();

  final List<AccessEntitlement> _entitlements = [
    AccessEntitlement(
      id: 'demo-entitlement-001',
      planId: 'demo-day',
      planName: 'واصل ون — يوم',
      status: 'active',
      startsAt: _now.subtract(const Duration(minutes: 12)),
      expiresAt: _now.add(const Duration(hours: 23, minutes: 48)),
      allowanceBytes: 2147483648,
      consumedBytes: 188743680,
      speedLimitKbps: 6144,
      maxConcurrentSessions: 1,
    ),
  ];
  final Map<String, WaselOnePurchaseResult> _purchasesByKey = {};

  static const _plans = [
    FederatedAccessPlan(
      id: 'demo-one-hour',
      name: 'واصل ون — ساعة',
      description: 'اتصال مرن لمدة ساعة عبر الشبكات الشريكة في منطقتك.',
      retailPrice: 300,
      currency: 'YER',
      validitySeconds: 3600,
      quotaBytes: 536870912,
      speedLimitKbps: 4096,
      maxConcurrentSessions: 1,
      partnerCount: 4,
    ),
    FederatedAccessPlan(
      id: 'demo-day',
      name: 'واصل ون — يوم',
      description: 'دخول واحد صالح لمدة 24 ساعة دون البحث عن كرت شبكة محددة.',
      retailPrice: 900,
      currency: 'YER',
      validitySeconds: 86400,
      quotaBytes: 2147483648,
      speedLimitKbps: 6144,
      maxConcurrentSessions: 1,
      partnerCount: 7,
    ),
    FederatedAccessPlan(
      id: 'demo-week',
      name: 'واصل ون — أسبوع',
      description: 'باقة تجريبية للتنقل اليومي بين نقاط الوصول المشاركة.',
      retailPrice: 4500,
      currency: 'YER',
      validitySeconds: 604800,
      quotaBytes: 10737418240,
      speedLimitKbps: 8192,
      maxConcurrentSessions: 1,
      partnerCount: 11,
    ),
  ];

  @override
  Future<List<FederatedAccessPlan>> getPublicPlans() async {
    await Future<void>.delayed(const Duration(milliseconds: 180));
    return List.of(_plans);
  }

  @override
  Future<List<AccessEntitlement>> getMyEntitlements() async {
    await Future<void>.delayed(const Duration(milliseconds: 180));
    return List.unmodifiable(_entitlements);
  }

  @override
  Future<WaselOnePurchaseResult> purchasePlan({
    required String planId,
    required String idempotencyKey,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final replay = _purchasesByKey[idempotencyKey];
    if (replay != null) {
      return WaselOnePurchaseResult(
        purchaseId: replay.purchaseId,
        entitlementId: replay.entitlementId,
        status: replay.status,
        amountPaid: replay.amountPaid,
        currency: replay.currency,
        newBalance: replay.newBalance,
        startsAt: replay.startsAt,
        expiresAt: replay.expiresAt,
        replayed: true,
      );
    }

    FederatedAccessPlan? plan;
    for (final item in _plans) {
      if (item.id == planId) {
        plan = item;
        break;
      }
    }
    if (plan == null) throw StateError('PLAN_UNAVAILABLE');
    final newBalance = _walletStore.debit(plan.retailPrice);
    final suffix = _purchasesByKey.length + 2;
    final startsAt = DateTime.now();
    final entitlementId = 'demo-entitlement-${suffix.toString().padLeft(3, '0')}';
    final result = WaselOnePurchaseResult(
      purchaseId: 'demo-purchase-${suffix.toString().padLeft(3, '0')}',
      entitlementId: entitlementId,
      status: 'completed',
      amountPaid: plan.retailPrice,
      currency: plan.currency,
      newBalance: newBalance,
      startsAt: startsAt,
      expiresAt: startsAt.add(plan.validity),
      replayed: false,
    );
    _purchasesByKey[idempotencyKey] = result;
    _entitlements.insert(
      0,
      AccessEntitlement(
        id: entitlementId,
        planId: plan.id,
        planName: plan.name,
        status: 'active',
        startsAt: startsAt,
        expiresAt: startsAt.add(plan.validity),
        allowanceBytes: plan.quotaBytes,
        consumedBytes: 0,
        speedLimitKbps: plan.speedLimitKbps,
        maxConcurrentSessions: plan.maxConcurrentSessions,
      ),
    );
    return result;
  }

  @override
  Future<RadiusAccessCredential> issueAccessCredential(
    String entitlementId,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!_entitlements.any(
      (item) => item.id == entitlementId && item.isUsable,
    )) {
      throw StateError('ENTITLEMENT_NOT_ACTIVE');
    }
    return RadiusAccessCredential(
      credentialId: 'demo-credential-001',
      username: 'w1-0123456789abcdef01234567',
      password: 'TEST-ONLY-482731',
      expiresAt: DateTime.now().add(const Duration(hours: 24)),
    );
  }
}
