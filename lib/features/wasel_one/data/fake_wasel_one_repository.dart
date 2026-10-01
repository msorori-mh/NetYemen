import 'wasel_one_repository.dart';
import '../domain/entities.dart';

class FakeWaselOneRepository implements WaselOneRepository {
  static final _now = DateTime.now();

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
    return [
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
  }

  @override
  Future<RadiusAccessCredential> issueAccessCredential(
    String entitlementId,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (entitlementId != 'demo-entitlement-001') {
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
