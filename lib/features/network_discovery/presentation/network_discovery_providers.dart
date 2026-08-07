import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/app_config.dart';
import '../../../core/error/app_exceptions.dart';
import '../../network_discovery/data/android_wifi_scan_service.dart';
import '../../network_discovery/data/demo_network_catalog_repository.dart';
import '../../network_discovery/data/fake_wifi_scan_service.dart';
import '../../network_discovery/data/network_catalog_repository.dart';
import '../../network_discovery/data/scan_matcher.dart';
import '../../network_discovery/data/supabase_network_catalog_repository.dart';
import '../../network_discovery/data/wifi_scan_service.dart';
import '../../network_discovery/domain/entities.dart';

final networkCatalogRepositoryProvider =
    Provider<NetworkCatalogRepository>((ref) {
  final config = ref.watch(appConfigProvider);
  if (config.isDemoMode || !config.isConfigured) {
    return DemoNetworkCatalogRepository();
  }
  return SupabaseNetworkCatalogRepository(Supabase.instance.client);
});

final wifiScanServiceProvider = Provider<WifiScanService>((ref) {
  final config = ref.watch(appConfigProvider);
  if (config.isDemoMode || !config.isConfigured) {
    return FakeWifiScanService();
  }
  return AndroidWifiScanService();
});

final appConfigProvider = Provider<AppConfig>((ref) {
  return AppConfig.fromEnvironment();
});

final networkCatalogProvider =
    AsyncNotifierProvider<NetworkCatalogNotifier, List<NetworkEntity>>(
  NetworkCatalogNotifier.new,
);

class NetworkCatalogNotifier extends AsyncNotifier<List<NetworkEntity>> {
  @override
  Future<List<NetworkEntity>> build() async {
    final repo = ref.read(networkCatalogRepositoryProvider);
    return repo.fetchApprovedNetworks();
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(networkCatalogRepositoryProvider);
      return repo.fetchApprovedNetworks();
    });
  }
}

final networkSearchQueryProvider = StateProvider<String>((ref) => '');

final filteredNetworksProvider =
    Provider<AsyncValue<List<NetworkEntity>>>((ref) {
  final networksAsync = ref.watch(networkCatalogProvider);
  final query = ref.watch(networkSearchQueryProvider).trim().toLowerCase();

  return networksAsync.whenData((networks) {
    if (query.isEmpty) return networks;
    return networks.where((n) => n.matchesSearch(query)).toList();
  });
});

final scanResultProvider =
    StateProvider<AsyncValue<ScanMatchResult>?>((ref) => null);

final scanNotifierProvider = Provider<ScanNotifier>((ref) {
  return ScanNotifier(ref);
});

class ScanNotifier {
  final Ref _ref;

  ScanNotifier(this._ref);

  Future<void> performScan() async {
    _ref.read(scanResultProvider.notifier).state = const AsyncValue.loading();

    try {
      final scanService = _ref.read(wifiScanServiceProvider);
      final catalogRepo = _ref.read(networkCatalogRepositoryProvider);

      final ssids = await scanService.performScan();
      final networks = await catalogRepo.fetchApprovedNetworks();

      final result = ScanMatcher.matchSsidsToNetworks(
        scannedSsids: ssids,
        networks: networks,
      );

      _ref.read(scanResultProvider.notifier).state = AsyncValue.data(result);
    } on ScanException catch (e) {
      _ref.read(scanResultProvider.notifier).state =
          AsyncValue.error(e, StackTrace.current);
    } catch (e) {
      _ref.read(scanResultProvider.notifier).state =
          AsyncValue.error(e, StackTrace.current);
    }
  }

  void clearScan() {
    _ref.read(scanResultProvider.notifier).state = null;
  }
}

final selectedScanSsidProvider = StateProvider<String?>((ref) => null);
