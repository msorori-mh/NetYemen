import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../network_discovery/presentation/network_discovery_providers.dart';
import '../data/admin_repository.dart';
import '../data/fake_admin_repository.dart';
import '../data/supabase_admin_repository.dart';
import '../domain/entities.dart';

final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  final config = ref.watch(appConfigProvider);
  if (config.isDemoMode || !config.isConfigured) {
    return FakeAdminRepository();
  }
  return SupabaseAdminRepository(Supabase.instance.client);
});

final adminDashboardKpiProvider = FutureProvider<AdminDashboardKpi>((
  ref,
) async {
  final repo = ref.watch(adminRepositoryProvider);
  return repo.fetchDashboardKpis();
});

final adminRequestsProvider =
    AsyncNotifierProvider<AdminRequestsNotifier, List<AdminNetworkRequest>>(
  AdminRequestsNotifier.new,
);

class AdminRequestsNotifier extends AsyncNotifier<List<AdminNetworkRequest>> {
  String? _statusFilter;

  @override
  Future<List<AdminNetworkRequest>> build() async {
    final repo = ref.read(adminRepositoryProvider);
    return repo.fetchPendingRequests(status: _statusFilter);
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(adminRepositoryProvider);
      return repo.fetchPendingRequests(status: _statusFilter);
    });
  }

  Future<void> setStatusFilter(String? status) async {
    _statusFilter = status;
    state = await AsyncValue.guard(() async {
      final repo = ref.read(adminRepositoryProvider);
      return repo.fetchPendingRequests(status: _statusFilter);
    });
  }
}

final adminRequestDetailProvider = AsyncNotifierProvider.family<
    AdminRequestDetailNotifier,
    AdminNetworkRequest,
    String>(AdminRequestDetailNotifier.new);

class AdminRequestDetailNotifier
    extends FamilyAsyncNotifier<AdminNetworkRequest, String> {
  @override
  Future<AdminNetworkRequest> build(String requestId) async {
    final repo = ref.read(adminRepositoryProvider);
    final requests = await repo.fetchPendingRequests();
    return requests.firstWhere((r) => r.id == requestId);
  }

  Future<void> resolve(
    String newStatus, {
    String? note,
    String? matchedNetworkId,
  }) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(adminRepositoryProvider);
      return repo.resolveRequest(
        arg,
        newStatus,
        note: note,
        matchedNetworkId: matchedNetworkId,
      );
    });
  }
}

final adminNetworksProvider =
    AsyncNotifierProvider<AdminNetworksNotifier, List<AdminNetwork>>(
  AdminNetworksNotifier.new,
);

class AdminNetworksNotifier extends AsyncNotifier<List<AdminNetwork>> {
  String? _statusFilter;
  String? _verificationFilter;

  @override
  Future<List<AdminNetwork>> build() async {
    final repo = ref.read(adminRepositoryProvider);
    return repo.fetchNetworks(
      status: _statusFilter,
      verificationStatus: _verificationFilter,
    );
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(adminRepositoryProvider);
      return repo.fetchNetworks(
        status: _statusFilter,
        verificationStatus: _verificationFilter,
      );
    });
  }

  Future<void> setFilters({String? status, String? verificationStatus}) async {
    _statusFilter = status;
    _verificationFilter = verificationStatus;
    state = await AsyncValue.guard(() async {
      final repo = ref.read(adminRepositoryProvider);
      return repo.fetchNetworks(
        status: _statusFilter,
        verificationStatus: _verificationFilter,
      );
    });
  }
}

final adminNetworkDetailProvider = AsyncNotifierProvider.family<
    AdminNetworkDetailNotifier,
    AdminNetwork,
    String>(AdminNetworkDetailNotifier.new);

class AdminNetworkDetailNotifier
    extends FamilyAsyncNotifier<AdminNetwork, String> {
  @override
  Future<AdminNetwork> build(String networkId) async {
    final repo = ref.read(adminRepositoryProvider);
    final networks = await repo.fetchNetworks();
    return networks.firstWhere((n) => n.id == networkId);
  }

  Future<void> approve({String? note}) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(adminRepositoryProvider);
      return repo.approveNetwork(arg, note: note);
    });
  }

  Future<void> suspend({String? reason}) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(adminRepositoryProvider);
      return repo.suspendNetwork(arg, reason: reason);
    });
  }
}

final adminNetworkAliasesProvider = AsyncNotifierProvider.family<
    AdminNetworkAliasesNotifier,
    List<AdminSsidAlias>,
    String>(AdminNetworkAliasesNotifier.new);

class AdminNetworkAliasesNotifier
    extends FamilyAsyncNotifier<List<AdminSsidAlias>, String> {
  @override
  Future<List<AdminSsidAlias>> build(String networkId) async {
    final repo = ref.read(adminRepositoryProvider);
    return repo.fetchNetworkAliases(networkId);
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(adminRepositoryProvider);
      return repo.fetchNetworkAliases(arg);
    });
  }

  Future<void> verifyAlias(String aliasId) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(adminRepositoryProvider);
      await repo.verifyAlias(aliasId);
      return repo.fetchNetworkAliases(arg);
    });
  }

  Future<void> rejectAlias(String aliasId, {String? reason}) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(adminRepositoryProvider);
      await repo.rejectAlias(aliasId, reason: reason);
      return repo.fetchNetworkAliases(arg);
    });
  }
}

final adminPackagesProvider =
    AsyncNotifierProvider<AdminPackagesNotifier, List<AdminPackageInventory>>(
  AdminPackagesNotifier.new,
);

class AdminPackagesNotifier extends AsyncNotifier<List<AdminPackageInventory>> {
  String? _networkIdFilter;

  @override
  Future<List<AdminPackageInventory>> build() async {
    final repo = ref.read(adminRepositoryProvider);
    return repo.fetchPackages(networkId: _networkIdFilter);
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(adminRepositoryProvider);
      return repo.fetchPackages(networkId: _networkIdFilter);
    });
  }

  Future<void> setNetworkFilter(String? networkId) async {
    _networkIdFilter = networkId;
    state = await AsyncValue.guard(() async {
      final repo = ref.read(adminRepositoryProvider);
      return repo.fetchPackages(networkId: _networkIdFilter);
    });
  }
}

final adminUsersProvider =
    AsyncNotifierProvider<AdminUsersNotifier, List<AdminUser>>(
  AdminUsersNotifier.new,
);

class AdminUsersNotifier extends AsyncNotifier<List<AdminUser>> {
  @override
  Future<List<AdminUser>> build() async {
    final repo = ref.read(adminRepositoryProvider);
    return repo.fetchUsers();
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(adminRepositoryProvider);
      return repo.fetchUsers();
    });
  }
}

final adminMembershipsProvider = AsyncNotifierProvider<AdminMembershipsNotifier,
    List<AdminNetworkMembership>>(AdminMembershipsNotifier.new);

class AdminMembershipsNotifier
    extends AsyncNotifier<List<AdminNetworkMembership>> {
  String? _networkIdFilter;

  @override
  Future<List<AdminNetworkMembership>> build() async {
    final repo = ref.read(adminRepositoryProvider);
    return repo.fetchNetworkMemberships(networkId: _networkIdFilter);
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(adminRepositoryProvider);
      return repo.fetchNetworkMemberships(networkId: _networkIdFilter);
    });
  }

  Future<void> setNetworkFilter(String? networkId) async {
    _networkIdFilter = networkId;
    state = await AsyncValue.guard(() async {
      final repo = ref.read(adminRepositoryProvider);
      return repo.fetchNetworkMemberships(networkId: _networkIdFilter);
    });
  }
}

final adminAuditEventsProvider =
    AsyncNotifierProvider<AdminAuditEventsNotifier, List<AdminAuditEvent>>(
  AdminAuditEventsNotifier.new,
);

class AdminAuditEventsNotifier extends AsyncNotifier<List<AdminAuditEvent>> {
  @override
  Future<List<AdminAuditEvent>> build() async {
    final repo = ref.read(adminRepositoryProvider);
    return repo.fetchAuditEvents();
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(adminRepositoryProvider);
      return repo.fetchAuditEvents();
    });
  }
}
