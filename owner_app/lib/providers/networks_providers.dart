import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/owner_networks_service.dart';

final networksServiceProvider = Provider<OwnerNetworksService>((ref) {
  return OwnerNetworksService();
});

final networkPackagesProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, networkId) async {
  final service = ref.watch(networksServiceProvider);
  return await service.getNetworkPackages(networkId);
});

final networkSsidAliasesProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, networkId) async {
  final service = ref.watch(networksServiceProvider);
  return await service.getNetworkSsidAliases(networkId);
});
