// lib/providers/inventory_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/owner_inventory_service.dart';

// Service singleton
final inventoryServiceProvider = Provider<OwnerInventoryService>((ref) {
  return OwnerInventoryService();
});

// الشبكة المختارة حالياً في شاشة المخزون
final selectedInventoryNetworkProvider = StateProvider<String?>((ref) => null);

// مخزون الباقات لشبكة معيّنة
final inventoryBalancesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, networkId) async {
  final service = ref.watch(inventoryServiceProvider);
  return await service.getInventoryBalances(networkId);
});

// إحصائيات الكروت مُجمَّعة حسب الحالة
final cardStateBreakdownProvider =
    FutureProvider.family<Map<String, int>, String>((ref, networkId) async {
  final service = ref.watch(inventoryServiceProvider);
  return await service.getCardStateBreakdown(networkId);
});

// بيانات بطاقات المخزون الوصفية
final cardVaultMetadataProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, networkId) async {
  final service = ref.watch(inventoryServiceProvider);
  return await service.getCardVaultMetadata(networkId);
});

// قائمة الباقات لشبكة (لنموذج الرفع)
final networkPackagesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, networkId) async {
  final service = ref.watch(inventoryServiceProvider);
  return await service.getNetworkPackages(networkId);
});
