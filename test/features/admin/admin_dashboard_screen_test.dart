import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/core/config/app_config.dart';
import 'package:netyemen/features/admin/data/admin_repository.dart';
import 'package:netyemen/features/admin/domain/entities.dart';
import 'package:netyemen/features/admin/presentation/admin_dashboard_screen.dart';
import 'package:netyemen/features/admin/presentation/admin_providers.dart';
import 'package:netyemen/providers/app_providers.dart';

class _FakeAdminRepository implements AdminRepository {
  @override
  Future<AdminDashboardKpi> fetchDashboardKpis() async {
    return const AdminDashboardKpi(
      activeNetworks: 7,
      pendingRequests: 3,
      approvedRequests: 5,
      rejectedRequests: 1,
      activePackages: 12,
      outOfStockPackages: 2,
      networkOwners: 4,
      networkOperators: 6,
    );
  }

  @override
  Future<List<AdminNetworkRequest>> fetchPendingRequests({
    String? status,
  }) async =>
      [];

  @override
  Future<AdminNetworkRequest> resolveRequest(
    String requestId,
    String newStatus, {
    String? note,
    String? matchedNetworkId,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<List<AdminNetwork>> fetchNetworks({
    String? status,
    String? verificationStatus,
  }) async =>
      [];

  @override
  Future<AdminNetwork> approveNetwork(String networkId, {String? note}) async {
    throw UnimplementedError();
  }

  @override
  Future<AdminNetwork> suspendNetwork(
    String networkId, {
    String? reason,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<List<AdminSsidAlias>> fetchNetworkAliases(String networkId) async =>
      [];

  @override
  Future<AdminSsidAlias> verifyAlias(String aliasId) async {
    throw UnimplementedError();
  }

  @override
  Future<AdminSsidAlias> rejectAlias(String aliasId, {String? reason}) async {
    throw UnimplementedError();
  }

  @override
  Future<List<AdminPackageInventory>> fetchPackages({
    String? networkId,
  }) async =>
      [];

  @override
  Future<List<AdminUser>> fetchUsers() async => [];

  @override
  Future<List<AdminNetworkMembership>> fetchNetworkMemberships({
    String? networkId,
  }) async =>
      [];

  @override
  Future<List<AdminAuditEvent>> fetchAuditEvents() async => [];

  @override
  Future<Map<String, dynamic>> ingestCardVaultBatch({
    required String networkId,
    required String packageId,
    required List<Map<String, dynamic>> cards,
    String keyVersion = 'v1-test',
  }) async =>
      {'batch_id': 'fake-batch', 'ingested_count': cards.length};
}

void main() {
  group('AdminDashboardScreen', () {
    testWidgets('renders KPI cards', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appConfigProvider.overrideWithValue(AppConfig.demo),
            adminRepositoryProvider.overrideWithValue(_FakeAdminRepository()),
            currentUserRolesProvider.overrideWith(
              (_) => const ['platform_admin'],
            ),
          ],
          child: const MaterialApp(home: AdminDashboardScreen()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('لوحة الإدارة'), findsOneWidget);
      expect(find.text('الشبكات النشطة'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(find.text('طلبات قيد المراجعة'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('الباقات النشطة'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
    });

    testWidgets('renders loading state initially', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appConfigProvider.overrideWithValue(AppConfig.demo),
            adminRepositoryProvider.overrideWithValue(_FakeAdminRepository()),
            currentUserRolesProvider.overrideWith(
              (_) => const ['platform_admin'],
            ),
          ],
          child: const MaterialApp(home: AdminDashboardScreen()),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
