import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/features/admin/data/fake_admin_repository.dart';

void main() {
  group('FakeAdminRepository', () {
    late FakeAdminRepository repository;

    setUp(() {
      repository = FakeAdminRepository();
    });

    test('fetchDashboardKpis returns non-negative counts', () async {
      final kpis = await repository.fetchDashboardKpis();
      expect(kpis.activeNetworks, greaterThanOrEqualTo(0));
      expect(kpis.pendingRequests, greaterThanOrEqualTo(0));
      expect(kpis.activePackages, greaterThanOrEqualTo(0));
    });

    test('fetchPendingRequests returns seeded requests', () async {
      final requests = await repository.fetchPendingRequests();
      expect(requests, isNotEmpty);
    });

    test('fetchPendingRequests filters by status', () async {
      final requests = await repository.fetchPendingRequests(
        status: 'submitted',
      );
      expect(requests.every((r) => r.status == 'submitted'), isTrue);
    });

    test('resolveRequest transitions status and preserves data', () async {
      final requests = await repository.fetchPendingRequests(
        status: 'submitted',
      );
      final request = requests.first;

      final resolved = await repository.resolveRequest(
        request.id,
        'under_review',
      );

      expect(resolved.status, 'under_review');
      expect(resolved.observedSsidDisplay, request.observedSsidDisplay);
    });

    test('resolveRequest supports matched_existing with network', () async {
      final requests = await repository.fetchPendingRequests(
        status: 'submitted',
      );
      final request = requests.first;

      final resolved = await repository.resolveRequest(
        request.id,
        'matched_existing',
        matchedNetworkId: 'demo-net-1',
      );

      expect(resolved.status, 'matched_existing');
      expect(resolved.matchedNetworkId, 'demo-net-1');
      expect(resolved.matchedNetworkName, 'شبكة يمن نت');
    });

    test('fetchNetworks returns seeded networks', () async {
      final networks = await repository.fetchNetworks();
      expect(networks, isNotEmpty);
    });

    test('fetchNetworks filters by status', () async {
      final networks = await repository.fetchNetworks(status: 'active');
      expect(networks.every((n) => n.status == 'active'), isTrue);
    });

    test('approveNetwork activates pending network', () async {
      final networks = await repository.fetchNetworks(
        status: 'pending_approval',
      );
      final network = networks.first;

      final approved = await repository.approveNetwork(network.id);
      expect(approved.status, 'active');
      expect(approved.verificationStatus, 'verified');
    });

    test('suspendNetwork suspends active network', () async {
      final networks = await repository.fetchNetworks(status: 'active');
      final network = networks.first;

      final suspended = await repository.suspendNetwork(network.id);
      expect(suspended.status, 'suspended');
    });

    test('fetchNetworkAliases returns aliases for network', () async {
      final aliases = await repository.fetchNetworkAliases('demo-net-1');
      expect(aliases, isNotEmpty);
      expect(aliases.every((a) => a.networkId == 'demo-net-1'), isTrue);
    });

    test('verifyAlias activates pending alias', () async {
      final aliases = await repository.fetchNetworkAliases('demo-net-1');
      final pending = aliases.firstWhere(
        (a) => a.status == 'pending_verification',
      );

      final verified = await repository.verifyAlias(pending.id);
      expect(verified.status, 'active');
    });

    test('rejectAlias rejects pending alias', () async {
      final aliases = await repository.fetchNetworkAliases('demo-net-2');
      final pending = aliases.firstWhere(
        (a) => a.status == 'pending_verification',
      );

      final rejected = await repository.rejectAlias(pending.id);
      expect(rejected.status, 'rejected');
    });

    test('fetchPackages includes inventory data', () async {
      final packages = await repository.fetchPackages();
      final withInventory = packages.firstWhere((p) => p.id == 'pkg-1');
      expect(withInventory.totalUnits, 100);
      expect(withInventory.availableUnits, 100);
      expect(withInventory.isOutOfStock, isFalse);
    });

    test('fetchPackages highlights out of stock packages', () async {
      final packages = await repository.fetchPackages();
      final outOfStock = packages.firstWhere((p) => p.id == 'pkg-2');
      expect(outOfStock.isOutOfStock, isTrue);
    });

    test('fetchUsers returns users with roles', () async {
      final users = await repository.fetchUsers();
      expect(users, isNotEmpty);
      final admin = users.firstWhere((u) => u.id == 'user-admin-1');
      expect(admin.roles, contains('platform_admin'));
    });

    test('test onboarding approval activates owner atomically', () async {
      final applications =
          await repository.fetchPendingTestOnboardingApplications();
      final ownerApplication = applications.firstWhere(
        (application) => application.requestedAccountType == 'network_owner',
      );

      await repository.reviewTestOnboardingApplication(
        applicationId: ownerApplication.id,
        decision: 'approve',
        reason: 'TEST_ONLY identity matched',
      );

      expect(
          await repository.fetchPendingTestOnboardingApplications(), isEmpty);
      final owner = (await repository.fetchUsers()).firstWhere(
        (user) => user.id == ownerApplication.userId,
      );
      expect(owner.accountStatus, 'active');
      expect(owner.roles, contains('network_owner'));
    });

    test('fetchNetworkMemberships returns memberships', () async {
      final memberships = await repository.fetchNetworkMemberships();
      expect(memberships, isNotEmpty);
    });

    test('fetchNetworkMemberships filters by network', () async {
      final memberships = await repository.fetchNetworkMemberships(
        networkId: 'demo-net-1',
      );
      expect(memberships.every((m) => m.networkId == 'demo-net-1'), isTrue);
    });

    test('fetchAuditEvents returns seeded events', () async {
      final events = await repository.fetchAuditEvents();
      expect(events, isNotEmpty);
    });

    test('card ingest takes pin cards and replays a batch key', () async {
      final cards = [
        {'pin': 'CARD-0001'},
        {'pin': 'CARD-0002', 'expires_at': '2027-01-01T00:00:00Z'},
      ];

      final first = await repository.ingestCardVaultBatch(
        networkId: 'demo-net-1',
        packageId: 'demo-pkg-1',
        cards: cards,
        batchKey: 'batch-key-1',
      );
      final replay = await repository.ingestCardVaultBatch(
        networkId: 'demo-net-1',
        packageId: 'demo-pkg-1',
        cards: cards,
        batchKey: 'batch-key-1',
      );

      expect(first['ingested_count'], 2);
      expect(first['replayed'], isFalse);
      expect(replay['batch_id'], first['batch_id']);
      expect(replay['replayed'], isTrue);
    });

    test('card ingest rejects what the server rejects', () async {
      Future<Map<String, dynamic>> ingest(List<Map<String, dynamic>> cards) {
        return repository.ingestCardVaultBatch(
          networkId: 'demo-net-1',
          packageId: 'demo-pkg-1',
          cards: cards,
        );
      }

      const blankPin = {'pin': '   '};
      const pinWithSpace = {'pin': 'HAS SPACE'};
      const legacyShape = {'ciphertext': 'not-a-pin'};

      await expectLater(ingest([]), throwsArgumentError);
      await expectLater(ingest([blankPin]), throwsArgumentError);
      await expectLater(ingest([pinWithSpace]), throwsArgumentError);
      await expectLater(ingest([legacyShape]), throwsArgumentError);
    });
  });
}
