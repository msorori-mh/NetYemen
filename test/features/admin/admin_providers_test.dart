import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/core/config/app_config.dart';
import 'package:netyemen/features/admin/data/admin_repository.dart';
import 'package:netyemen/features/admin/domain/entities.dart';
import 'package:netyemen/features/admin/presentation/admin_providers.dart';
import 'package:netyemen/features/network_discovery/presentation/network_discovery_providers.dart';
import 'package:netyemen/providers/app_providers.dart';

class _FakeAdminRepository implements AdminRepository {
  final AdminDashboardKpi kpis;
  final List<AdminNetworkRequest> requests;

  _FakeAdminRepository({
    required this.kpis,
    required this.requests,
  });

  @override
  Future<AdminDashboardKpi> fetchDashboardKpis() async => kpis;

  @override
  Future<List<AdminNetworkRequest>> fetchPendingRequests({String? status}) async {
    if (status == null) return requests;
    return requests.where((r) => r.status == status).toList();
  }

  @override
  Future<AdminNetworkRequest> resolveRequest(
    String requestId,
    String newStatus, {
    String? note,
    String? matchedNetworkId,
  }) async {
    final request = requests.firstWhere((r) => r.id == requestId);
    return AdminNetworkRequest(
      id: request.id,
      requesterUserId: request.requesterUserId,
      observedSsidDisplay: request.observedSsidDisplay,
      status: newStatus,
      createdAt: request.createdAt,
    );
  }

  @override
  Future<List<AdminNetwork>> fetchNetworks({
    String? status,
    String? verificationStatus,
  }) async => [];

  @override
  Future<AdminNetwork> approveNetwork(String networkId, {String? note}) async {
    throw UnimplementedError();
  }

  @override
  Future<AdminNetwork> suspendNetwork(String networkId, {String? reason}) async {
    throw UnimplementedError();
  }

  @override
  Future<List<AdminSsidAlias>> fetchNetworkAliases(String networkId) async => [];

  @override
  Future<AdminSsidAlias> verifyAlias(String aliasId) async {
    throw UnimplementedError();
  }

  @override
  Future<AdminSsidAlias> rejectAlias(String aliasId, {String? reason}) async {
    throw UnimplementedError();
  }

  @override
  Future<List<AdminPackageInventory>> fetchPackages({String? networkId}) async => [];

  @override
  Future<List<AdminUser>> fetchUsers() async => [];

  @override
  Future<List<AdminNetworkMembership>> fetchNetworkMemberships({
    String? networkId,
  }) async => [];

  @override
  Future<List<AdminAuditEvent>> fetchAuditEvents() async => [];
}

void main() {
  group('AdminProviders', () {
    ProviderContainer createContainer({
      required AdminRepository repository,
      AppConfig config = AppConfig.demo,
    }) {
      return ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(config),
          adminRepositoryProvider.overrideWithValue(repository),
          currentUserRolesProvider.overrideWith((_) => const ['platform_admin']),
        ],
      );
    }

    test('adminDashboardKpiProvider returns repository KPIs', () async {
      const kpis = AdminDashboardKpi(
        activeNetworks: 5,
        pendingRequests: 3,
        approvedRequests: 2,
        rejectedRequests: 1,
        activePackages: 10,
        outOfStockPackages: 0,
        networkOwners: 4,
        networkOperators: 2,
      );

      final container = createContainer(
        repository: _FakeAdminRepository(kpis: kpis, requests: []),
      );

      final result = await container.read(adminDashboardKpiProvider.future);
      expect(result.activeNetworks, 5);
      expect(result.pendingRequests, 3);
    });

    test('adminRequestsProvider fetches and filters requests', () async {
      final requests = [
        AdminNetworkRequest(
          id: 'r-1',
          requesterUserId: 'u-1',
          observedSsidDisplay: 'SSID-1',
          status: 'submitted',
          createdAt: DateTime.now(),
        ),
        AdminNetworkRequest(
          id: 'r-2',
          requesterUserId: 'u-2',
          observedSsidDisplay: 'SSID-2',
          status: 'under_review',
          createdAt: DateTime.now(),
        ),
      ];

      final container = createContainer(
        repository: _FakeAdminRepository(kpis: const AdminDashboardKpi(
          activeNetworks: 0,
          pendingRequests: 0,
          approvedRequests: 0,
          rejectedRequests: 0,
          activePackages: 0,
          outOfStockPackages: 0,
          networkOwners: 0,
          networkOperators: 0,
        ), requests: requests),
      );

      final allRequests = await container.read(adminRequestsProvider.future);
      expect(allRequests.length, 2);

      await container.read(adminRequestsProvider.notifier).setStatusFilter('submitted');
      final filtered = await container.read(adminRequestsProvider.future);
      expect(filtered.length, 1);
      expect(filtered.first.status, 'submitted');
    });
  });
}
