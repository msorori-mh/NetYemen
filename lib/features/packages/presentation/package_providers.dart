import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../network_discovery/domain/entities.dart';
import '../../network_discovery/presentation/network_discovery_providers.dart';
import '../data/fake_package_repository.dart';
import '../data/package_repository.dart';
import '../data/supabase_package_repository.dart';
import '../domain/entities.dart';

final packageRepositoryProvider = Provider<PackageRepository>((ref) {
  final config = ref.watch(appConfigProvider);
  if (config.isDemoMode || !config.isConfigured) {
    return FakePackageRepository();
  }
  return SupabasePackageRepository(Supabase.instance.client);
});

final ownedNetworksProvider = FutureProvider<List<NetworkEntity>>((ref) async {
  final repo = ref.watch(packageRepositoryProvider);
  return repo.fetchOwnedNetworks();
});

final publicPackagesProvider = FutureProvider.family<List<NetworkPackage>, String>(
  (ref, networkId) async {
    final repo = ref.watch(packageRepositoryProvider);
    return repo.fetchPublicPackages(networkId);
  },
);

final networkPackagesProvider = FutureProvider.family<List<NetworkPackage>, String>(
  (ref, networkId) async {
    final repo = ref.watch(packageRepositoryProvider);
    return repo.fetchNetworkPackages(networkId);
  },
);

final packageBalanceProvider = FutureProvider.family<PackageInventoryBalance?, String>(
  (ref, packageId) async {
    final repo = ref.watch(packageRepositoryProvider);
    return repo.fetchPackageBalance(packageId);
  },
);

final networkMovementsProvider = FutureProvider.family<List<PackageInventoryMovement>, String>(
  (ref, networkId) async {
    final repo = ref.watch(packageRepositoryProvider);
    return repo.fetchNetworkMovements(networkId);
  },
);

class PackageNotifier extends FamilyAsyncNotifier<NetworkPackage, String> {
  @override
  Future<NetworkPackage> build(String packageId) async {
    final repo = ref.read(packageRepositoryProvider);
    final package = await repo.fetchPackage(packageId);
    if (package == null) {
      throw StateError('Package not found');
    }
    return package;
  }

  Future<void> publish() async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(packageRepositoryProvider);
      return repo.publishPackage(arg);
    });
  }

  Future<void> deactivate() async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(packageRepositoryProvider);
      return repo.deactivatePackage(arg);
    });
  }

  Future<void> archive() async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(packageRepositoryProvider);
      return repo.archivePackage(arg);
    });
  }
}

final packageNotifierProvider = AsyncNotifierProvider.family<PackageNotifier, NetworkPackage, String>(
  PackageNotifier.new,
);
