import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/core/config/app_config.dart';
import 'package:netyemen/features/admin/data/admin_repository.dart';
import 'package:netyemen/features/admin/domain/entities.dart';
import 'package:netyemen/features/admin/presentation/admin_providers.dart';
import 'package:netyemen/features/admin/presentation/admin_requests_screen.dart';
import 'package:netyemen/providers/app_providers.dart';

class _FakeAdminRepository implements AdminRepository {
  final List<AdminNetworkRequest> _requests;

  _FakeAdminRepository(this._requests);

  @override
  Future<List<AdminNetworkRequest>> fetchPendingRequests({String? status}) async {
    await Future.delayed(const Duration(milliseconds: 50));
    if (status == null) return _requests;
    return _requests.where((r) => r.status == status).toList();
  }

  @override
  Future<AdminNetworkRequest> resolveRequest(
    String requestId,
    String newStatus, {
    String? note,
    String? matchedNetworkId,
  }) async {
    final request = _requests.firstWhere((r) => r.id == requestId);
    return AdminNetworkRequest(
      id: request.id,
      requesterUserId: request.requesterUserId,
      observedSsidDisplay: request.observedSsidDisplay,
      status: newStatus,
      createdAt: request.createdAt,
    );
  }

  @override
  Future<AdminDashboardKpi> fetchDashboardKpis() async {
    return const AdminDashboardKpi(
      activeNetworks: 0,
      pendingRequests: 0,
      approvedRequests: 0,
      rejectedRequests: 0,
      activePackages: 0,
      outOfStockPackages: 0,
      networkOwners: 0,
      networkOperators: 0,
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

  @override
  Future<Map<String, dynamic>> ingestCardVaultBatch({
    required String networkId,
    required String packageId,
    required List<Map<String, dynamic>> cards,
    String keyVersion = 'v1-test',
  }) async => {'batch_id': 'fake-batch', 'ingested_count': cards.length};
}

void main() {
  group('AdminRequestsScreen', () {
    testWidgets('renders request list with resolve buttons on cards',
        (tester) async {
      final requests = [
        AdminNetworkRequest(
          id: 'r-1',
          requesterUserId: 'u-1',
          observedSsidDisplay: 'DemoSSID',
          proposedNetworkName: 'شبكة تجريبية',
          status: 'submitted',
          requesterName: 'مستخدم تجريبي',
          createdAt: DateTime.now(),
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appConfigProvider.overrideWithValue(AppConfig.demo),
            adminRepositoryProvider.overrideWithValue(
              _FakeAdminRepository(requests),
            ),
            currentUserRolesProvider.overrideWith((_) => const ['platform_admin']),
          ],
          child: const MaterialApp(
            home: AdminRequestsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('طلبات الشبكات'), findsOneWidget);
      expect(find.text('DemoSSID'), findsOneWidget);
      expect(find.text('مستخدم تجريبي'), findsOneWidget);
      expect(find.text('شبكة تجريبية'), findsOneWidget);
    });

    testWidgets('filters requests by status', (tester) async {
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

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appConfigProvider.overrideWithValue(AppConfig.demo),
            adminRepositoryProvider.overrideWithValue(
              _FakeAdminRepository(requests),
            ),
            currentUserRolesProvider.overrideWith((_) => const ['platform_admin']),
          ],
          child: const MaterialApp(
            home: AdminRequestsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('SSID-1'), findsOneWidget);
      expect(find.text('SSID-2'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'قيد المراجعة'));
      await tester.pumpAndSettle();

      expect(find.text('SSID-1'), findsNothing);
      expect(find.text('SSID-2'), findsOneWidget);
    });
  });
}
