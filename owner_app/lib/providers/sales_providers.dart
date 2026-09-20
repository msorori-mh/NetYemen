// lib/providers/sales_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/owner_sales_service.dart';

// Service singleton
final salesServiceProvider = Provider<OwnerSalesService>((ref) {
  return OwnerSalesService();
});

// الشبكة المختارة حالياً في شاشة المبيعات
final selectedSalesNetworkProvider = StateProvider<String?>((ref) => null);

// ملخّص تجاري لشبكة واحدة (أو كل الشبكات إذا null)
final commercialSummaryProvider =
    FutureProvider.family<Map<String, dynamic>, String?>((ref, networkId) async {
  final service = ref.watch(salesServiceProvider);
  return await service.getCommercialSummary(networkId: networkId);
});

// قائمة التسويات
final settlementsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String?>((ref, networkId) async {
  final service = ref.watch(salesServiceProvider);
  return await service.getSettlements(networkId: networkId);
});
