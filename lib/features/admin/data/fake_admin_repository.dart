import '../../../core/utils/uuid_generator.dart';
import '../domain/entities.dart';
import 'admin_repository.dart';

class FakeAdminRepository implements AdminRepository {
  final List<AdminNetwork> _networks = [];
  final List<AdminNetworkRequest> _requests = [];
  final List<AdminSsidAlias> _aliases = [];
  final List<AdminPackageInventory> _packages = [];
  final List<AdminUser> _users = [];
  final List<AdminNetworkMembership> _memberships = [];
  final List<AdminAuditEvent> _auditEvents = [];

  FakeAdminRepository() {
    _seedDemoData();
  }

  void _seedDemoData() {
    final now = DateTime.now();

    _networks.addAll([
      AdminNetwork(
        id: 'demo-net-1',
        commercialName: 'شبكة يمن نت',
        description: 'شبكة إنترنت سريعة في صنعاء',
        governorate: 'أمانة العاصمة',
        city: 'صنعاء',
        district: 'الوحدة',
        status: 'active',
        verificationStatus: 'verified',
        createdAt: now.subtract(const Duration(days: 30)),
        ownerNames: const ['أحمد علي'],
      ),
      AdminNetwork(
        id: 'demo-net-2',
        commercialName: 'شبكة عدن للاتصالات',
        description: 'خدمة إنترنت مستقرة في عدن',
        governorate: 'عدن',
        city: 'كريتر',
        district: 'المعلا',
        status: 'pending_approval',
        verificationStatus: 'unverified',
        createdAt: now.subtract(const Duration(days: 5)),
        ownerNames: const ['سارة محمد'],
      ),
      AdminNetwork(
        id: 'demo-net-3',
        commercialName: 'شبكة تعز السريعة',
        description: 'باقات اقتصادية في تعز',
        governorate: 'تعز',
        city: 'تعز',
        district: 'المركز',
        status: 'suspended',
        verificationStatus: 'verified',
        createdAt: now.subtract(const Duration(days: 60)),
        ownerNames: const ['خالد عمر'],
      ),
    ]);

    _requests.addAll([
      AdminNetworkRequest(
        id: 'req-1',
        requesterUserId: 'user-1',
        observedSsidDisplay: 'YemenNet_New',
        proposedNetworkName: 'شبكة يمن نت فرع جديد',
        governorate: 'أمانة العاصمة',
        city: 'صنعاء',
        status: 'submitted',
        createdAt: now.subtract(const Duration(days: 2)),
        requesterName: 'محمد عبدالله',
      ),
      AdminNetworkRequest(
        id: 'req-2',
        requesterUserId: 'user-2',
        observedSsidDisplay: 'AdenWiFi_2',
        proposedNetworkName: 'عدن واي فاي 2',
        governorate: 'عدن',
        city: 'كريتر',
        status: 'under_review',
        createdAt: now.subtract(const Duration(days: 1)),
        requesterName: 'فاطمة حسن',
      ),
      AdminNetworkRequest(
        id: 'req-3',
        requesterUserId: 'user-3',
        observedSsidDisplay: 'TaizSpeed',
        proposedNetworkName: 'تعز السريعة فرع الشماسي',
        governorate: 'تعز',
        city: 'تعز',
        status: 'matched_existing',
        matchedNetworkId: 'demo-net-3',
        matchedNetworkName: 'شبكة تعز السريعة',
        resolutionNote: 'مطابقة مع شبكة موجودة',
        createdAt: now.subtract(const Duration(days: 4)),
        resolvedAt: now.subtract(const Duration(days: 3)),
        requesterName: 'عبدالرحمن صالح',
      ),
    ]);

    _aliases.addAll([
      AdminSsidAlias(
        id: 'alias-1a',
        networkId: 'demo-net-1',
        ssidDisplay: 'YemenNet_Fast',
        ssidNormalized: 'yemennet-fast',
        status: 'active',
        createdAt: now.subtract(const Duration(days: 25)),
      ),
      AdminSsidAlias(
        id: 'alias-1b',
        networkId: 'demo-net-1',
        ssidDisplay: 'YemenNet-5G',
        ssidNormalized: 'yemennet-5g',
        status: 'pending_verification',
        createdAt: now.subtract(const Duration(days: 2)),
      ),
      AdminSsidAlias(
        id: 'alias-2a',
        networkId: 'demo-net-2',
        ssidDisplay: 'AdenConnect',
        ssidNormalized: 'adenconnect',
        status: 'pending_verification',
        createdAt: now.subtract(const Duration(days: 4)),
      ),
    ]);

    _packages.addAll([
      AdminPackageInventory(
        id: 'pkg-1',
        networkId: 'demo-net-1',
        name: 'باقة يومية',
        description: 'إنترنت سريع لمدة 24 ساعة',
        price: 500,
        currency: 'YER',
        durationValue: 1,
        durationUnit: 'day',
        speedMbps: 10,
        packageType: 'time',
        status: 'active',
        isPublic: true,
        sortOrder: 1,
        createdAt: now.subtract(const Duration(days: 20)),
        totalUnits: 100,
        availableUnits: 100,
      ),
      AdminPackageInventory(
        id: 'pkg-2',
        networkId: 'demo-net-1',
        name: 'باقة شهرية',
        description: 'باقة اقتصادية لمدة 30 يوم',
        price: 8000,
        currency: 'YER',
        durationValue: 1,
        durationUnit: 'month',
        speedMbps: 50,
        packageType: 'time',
        status: 'active',
        isPublic: true,
        sortOrder: 2,
        createdAt: now.subtract(const Duration(days: 20)),
        totalUnits: 50,
        availableUnits: 0,
      ),
      AdminPackageInventory(
        id: 'pkg-3',
        networkId: 'demo-net-2',
        name: 'باقة تجريبية',
        description: 'باقة قيد التجهيز',
        price: 1000,
        currency: 'YER',
        packageType: 'time',
        status: 'draft',
        isPublic: false,
        sortOrder: 1,
        createdAt: now.subtract(const Duration(days: 3)),
        totalUnits: 0,
        availableUnits: 0,
      ),
    ]);

    _users.addAll([
      const AdminUser(
        id: 'user-admin-1',
        fullName: 'مدير المنصة',
        accountStatus: 'active',
        roles: ['platform_admin'],
      ),
      const AdminUser(
        id: 'user-support-1',
        fullName: 'وكيل الدعم',
        accountStatus: 'active',
        roles: ['support_agent'],
      ),
      const AdminUser(
        id: 'user-owner-1',
        fullName: 'أحمد علي',
        accountStatus: 'active',
        roles: ['customer', 'network_owner'],
      ),
      const AdminUser(
        id: 'user-operator-1',
        fullName: 'سارة محمد',
        accountStatus: 'active',
        roles: ['customer', 'network_operator'],
      ),
    ]);

    _memberships.addAll([
      AdminNetworkMembership(
        networkId: 'demo-net-1',
        userId: 'user-owner-1',
        membershipRole: 'owner',
        status: 'active',
        fullName: 'أحمد علي',
        createdAt: now.subtract(const Duration(days: 30)),
      ),
      AdminNetworkMembership(
        networkId: 'demo-net-1',
        userId: 'user-operator-1',
        membershipRole: 'operator',
        status: 'active',
        fullName: 'سارة محمد',
        createdAt: now.subtract(const Duration(days: 25)),
      ),
      AdminNetworkMembership(
        networkId: 'demo-net-2',
        userId: 'user-owner-2',
        membershipRole: 'owner',
        status: 'active',
        fullName: 'سارة محمد',
        createdAt: now.subtract(const Duration(days: 5)),
      ),
    ]);

    _auditEvents.addAll([
      AdminAuditEvent(
        id: 'audit-1',
        occurredAt: now.subtract(const Duration(days: 1)),
        actorUserId: 'user-admin-1',
        actorRole: 'platform_admin',
        action: 'ADMIN_APPROVE_NETWORK',
        entityType: 'network',
        entityId: 'demo-net-1',
        result: 'success',
        reasonCode: 'ADMIN_APPROVE',
      ),
      AdminAuditEvent(
        id: 'audit-2',
        occurredAt: now.subtract(const Duration(hours: 6)),
        actorUserId: 'user-support-1',
        actorRole: 'support_agent',
        action: 'RESOLVE_NETWORK_REQUEST',
        entityType: 'network_addition_request',
        entityId: 'req-3',
        result: 'success',
        reasonCode: 'MATCHED_EXISTING',
      ),
    ]);
  }

  @override
  Future<AdminDashboardKpi> fetchDashboardKpis() async {
    await Future.delayed(const Duration(milliseconds: 200));
    return AdminDashboardKpi(
      activeNetworks: _networks
          .where(
            (n) => n.status == 'active' && n.verificationStatus == 'verified',
          )
          .length,
      pendingRequests: _requests
          .where((r) => r.status == 'submitted' || r.status == 'under_review')
          .length,
      approvedRequests: _requests.where((r) => r.status == 'approved').length,
      rejectedRequests: _requests.where((r) => r.status == 'rejected').length,
      activePackages: _packages.where((p) => p.status == 'active').length,
      outOfStockPackages: _packages.where((p) => p.availableUnits <= 0).length,
      networkOwners:
          _users.where((u) => u.roles.contains('network_owner')).length,
      networkOperators:
          _users.where((u) => u.roles.contains('network_operator')).length,
    );
  }

  @override
  Future<List<AdminNetworkRequest>> fetchPendingRequests({
    String? status,
  }) async {
    await Future.delayed(const Duration(milliseconds: 200));
    if (status == null || status.isEmpty) {
      return List.of(_requests);
    }
    return _requests.where((r) => r.status == status).toList();
  }

  @override
  Future<AdminNetworkRequest> resolveRequest(
    String requestId,
    String newStatus, {
    String? note,
    String? matchedNetworkId,
  }) async {
    await Future.delayed(const Duration(milliseconds: 150));
    final index = _requests.indexWhere((r) => r.id == requestId);
    if (index == -1) throw StateError('الطلب غير موجود');

    final original = _requests[index];
    final now = DateTime.now();

    String? matchedName;
    String? matchedStatus;
    String? matchedVerification;
    if (matchedNetworkId != null) {
      final network = _networks.firstWhere(
        (n) => n.id == matchedNetworkId,
        orElse: () => throw StateError('الشبكة المطابقة غير موجودة'),
      );
      matchedName = network.commercialName;
      matchedStatus = network.status;
      matchedVerification = network.verificationStatus;
    }

    final resolved = AdminNetworkRequest(
      id: original.id,
      requesterUserId: original.requesterUserId,
      idempotencyKey: original.idempotencyKey,
      proposedNetworkName: original.proposedNetworkName,
      observedSsidDisplay: original.observedSsidDisplay,
      observedSsidNormalized: original.observedSsidNormalized,
      governorate: original.governorate,
      city: original.city,
      district: original.district,
      notes: original.notes,
      status: newStatus,
      duplicateOf: original.duplicateOf,
      matchedNetworkId: matchedNetworkId ?? original.matchedNetworkId,
      resolutionNote: note ?? original.resolutionNote,
      createdAt: original.createdAt,
      updatedAt: now,
      resolvedAt: _isTerminal(newStatus) ? now : original.resolvedAt,
      resolvedBy: _isTerminal(newStatus) ? 'fake-admin' : original.resolvedBy,
      requesterName: original.requesterName,
      matchedNetworkName: matchedName ?? original.matchedNetworkName,
      matchedNetworkStatus: matchedStatus ?? original.matchedNetworkStatus,
      matchedNetworkVerificationStatus:
          matchedVerification ?? original.matchedNetworkVerificationStatus,
    );

    _requests[index] = resolved;
    _recordAudit(
      'RESOLVE_NETWORK_REQUEST',
      'network_addition_request',
      requestId,
    );
    return resolved;
  }

  bool _isTerminal(String status) {
    return status == 'approved' ||
        status == 'rejected' ||
        status == 'matched_existing';
  }

  @override
  Future<List<AdminNetwork>> fetchNetworks({
    String? status,
    String? verificationStatus,
  }) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return _networks.where((n) {
      if (status != null && status.isNotEmpty && n.status != status)
        return false;
      if (verificationStatus != null &&
          verificationStatus.isNotEmpty &&
          n.verificationStatus != verificationStatus) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Future<AdminNetwork> approveNetwork(String networkId, {String? note}) async {
    await Future.delayed(const Duration(milliseconds: 150));
    final index = _networks.indexWhere((n) => n.id == networkId);
    if (index == -1) throw StateError('الشبكة غير موجودة');

    final original = _networks[index];
    final approved = AdminNetwork(
      id: original.id,
      commercialName: original.commercialName,
      description: original.description,
      governorate: original.governorate,
      city: original.city,
      district: original.district,
      status: 'active',
      verificationStatus: 'verified',
      createdBy: original.createdBy,
      approvedBy: 'fake-admin',
      approvedAt: DateTime.now(),
      createdAt: original.createdAt,
      updatedAt: DateTime.now(),
      ownerNames: original.ownerNames,
    );

    _networks[index] = approved;
    _recordAudit('ADMIN_APPROVE_NETWORK', 'network', networkId);
    return approved;
  }

  @override
  Future<AdminNetwork> suspendNetwork(
    String networkId, {
    String? reason,
  }) async {
    await Future.delayed(const Duration(milliseconds: 150));
    final index = _networks.indexWhere((n) => n.id == networkId);
    if (index == -1) throw StateError('الشبكة غير موجودة');

    final original = _networks[index];
    final suspended = AdminNetwork(
      id: original.id,
      commercialName: original.commercialName,
      description: original.description,
      governorate: original.governorate,
      city: original.city,
      district: original.district,
      status: 'suspended',
      verificationStatus: original.verificationStatus,
      createdBy: original.createdBy,
      approvedBy: original.approvedBy,
      approvedAt: original.approvedAt,
      createdAt: original.createdAt,
      updatedAt: DateTime.now(),
      ownerNames: original.ownerNames,
    );

    _networks[index] = suspended;
    _recordAudit('ADMIN_SUSPEND_NETWORK', 'network', networkId);
    return suspended;
  }

  @override
  Future<List<AdminSsidAlias>> fetchNetworkAliases(String networkId) async {
    await Future.delayed(const Duration(milliseconds: 150));
    return _aliases.where((a) => a.networkId == networkId).toList();
  }

  @override
  Future<AdminSsidAlias> verifyAlias(String aliasId) async {
    await Future.delayed(const Duration(milliseconds: 150));
    final index = _aliases.indexWhere((a) => a.id == aliasId);
    if (index == -1) throw StateError('الاسم المستعار غير موجود');

    final original = _aliases[index];
    final verified = AdminSsidAlias(
      id: original.id,
      networkId: original.networkId,
      ssidDisplay: original.ssidDisplay,
      ssidNormalized: original.ssidNormalized,
      status: 'active',
      verifiedAt: DateTime.now(),
      verifiedBy: 'fake-admin',
      createdAt: original.createdAt,
      updatedAt: DateTime.now(),
    );

    _aliases[index] = verified;
    _recordAudit('ADMIN_VERIFY_SSID_ALIAS', 'network_ssid_alias', aliasId);
    return verified;
  }

  @override
  Future<AdminSsidAlias> rejectAlias(String aliasId, {String? reason}) async {
    await Future.delayed(const Duration(milliseconds: 150));
    final index = _aliases.indexWhere((a) => a.id == aliasId);
    if (index == -1) throw StateError('الاسم المستعار غير موجود');

    final original = _aliases[index];
    final rejected = AdminSsidAlias(
      id: original.id,
      networkId: original.networkId,
      ssidDisplay: original.ssidDisplay,
      ssidNormalized: original.ssidNormalized,
      status: 'rejected',
      verifiedAt: original.verifiedAt,
      verifiedBy: original.verifiedBy,
      createdAt: original.createdAt,
      updatedAt: DateTime.now(),
    );

    _aliases[index] = rejected;
    _recordAudit('ADMIN_REJECT_SSID_ALIAS', 'network_ssid_alias', aliasId);
    return rejected;
  }

  @override
  Future<List<AdminPackageInventory>> fetchPackages({String? networkId}) async {
    await Future.delayed(const Duration(milliseconds: 200));
    if (networkId == null || networkId.isEmpty) {
      return List.of(_packages);
    }
    return _packages.where((p) => p.networkId == networkId).toList();
  }

  @override
  Future<List<AdminUser>> fetchUsers() async {
    await Future.delayed(const Duration(milliseconds: 200));
    return List.of(_users);
  }

  @override
  Future<List<AdminNetworkMembership>> fetchNetworkMemberships({
    String? networkId,
  }) async {
    await Future.delayed(const Duration(milliseconds: 150));
    if (networkId == null || networkId.isEmpty) {
      return List.of(_memberships);
    }
    return _memberships.where((m) => m.networkId == networkId).toList();
  }

  @override
  Future<List<AdminAuditEvent>> fetchAuditEvents() async {
    await Future.delayed(const Duration(milliseconds: 200));
    return List.of(_auditEvents)
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
  }

  @override
  Future<Map<String, dynamic>> ingestCardVaultBatch({
    required String networkId,
    required String packageId,
    required List<Map<String, dynamic>> cards,
    String keyVersion = 'v1-test',
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    for (final card in cards) {
      if (card['ciphertext'] == null ||
          (card['ciphertext'] as String).isEmpty) {
        throw ArgumentError('INVALID_CARD: ciphertext is required');
      }
      if (card['nonce'] == null || (card['nonce'] as String).isEmpty) {
        throw ArgumentError('INVALID_CARD: nonce is required');
      }
    }
    _recordAudit('ADMIN_INGEST_CARD_VAULT_BATCH', 'card_vault', packageId);
    return {
      'batch_id': 'batch-${UuidGenerator.generateV4()}',
      'ingested_count': cards.length,
    };
  }

  void _recordAudit(String action, String entityType, String entityId) {
    _auditEvents.add(
      AdminAuditEvent(
        id: 'audit-${UuidGenerator.generateV4()}',
        occurredAt: DateTime.now(),
        actorUserId: 'fake-admin',
        actorRole: 'platform_admin',
        action: action,
        entityType: entityType,
        entityId: entityId,
        result: 'success',
      ),
    );
  }
}
