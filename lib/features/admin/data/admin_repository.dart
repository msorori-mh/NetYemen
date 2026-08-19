import '../domain/entities.dart';

abstract class AdminRepository {
  /// Fetch admin dashboard KPIs.
  Future<AdminDashboardKpi> fetchDashboardKpis();

  /// Fetch network addition requests, optionally filtered by status.
  Future<List<AdminNetworkRequest>> fetchPendingRequests({String? status});

  /// Resolve a network addition request to a new status.
  Future<AdminNetworkRequest> resolveRequest(
    String requestId,
    String newStatus, {
    String? note,
    String? matchedNetworkId,
  });

  /// Fetch networks, optionally filtered by status or verification status.
  Future<List<AdminNetwork>> fetchNetworks({
    String? status,
    String? verificationStatus,
  });

  /// Approve a pending network.
  Future<AdminNetwork> approveNetwork(String networkId, {String? note});

  /// Suspend an active network.
  Future<AdminNetwork> suspendNetwork(String networkId, {String? reason});

  /// Fetch SSID aliases for a network.
  Future<List<AdminSsidAlias>> fetchNetworkAliases(String networkId);

  /// Verify an SSID alias.
  Future<AdminSsidAlias> verifyAlias(String aliasId);

  /// Reject an SSID alias.
  Future<AdminSsidAlias> rejectAlias(String aliasId, {String? reason});

  /// Fetch packages with inventory, optionally filtered by network.
  Future<List<AdminPackageInventory>> fetchPackages({String? networkId});

  /// Fetch all users and their platform roles.
  Future<List<AdminUser>> fetchUsers();

  /// Grant or revoke an administratively assignable platform role.
  Future<void> setUserPlatformRole({
    required String userId,
    required String role,
    required bool enabled,
  }) {
    throw UnsupportedError('Identity mutations are not supported');
  }

  /// Change a user account lifecycle status through the guarded admin RPC.
  Future<void> setUserAccountStatus({
    required String userId,
    required String status,
    String? reason,
  }) {
    throw UnsupportedError('Identity mutations are not supported');
  }

  /// Fetch network memberships, optionally filtered by network.
  Future<List<AdminNetworkMembership>> fetchNetworkMemberships({
    String? networkId,
  });

  /// Fetch audit events.
  Future<List<AdminAuditEvent>> fetchAuditEvents();

  /// Ingest an encrypted card vault batch for a package.
  Future<Map<String, dynamic>> ingestCardVaultBatch({
    required String networkId,
    required String packageId,
    required List<Map<String, dynamic>> cards,
    String keyVersion,
  });
}
