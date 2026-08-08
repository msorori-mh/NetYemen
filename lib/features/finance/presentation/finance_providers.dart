// lib/features/finance/presentation/finance_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../providers/app_providers.dart';
import '../data/finance_repository.dart';
import '../data/supabase_finance_repository.dart';
import '../data/fake_finance_repository.dart';

final financeRepositoryProvider = Provider<FinanceRepository>((ref) {
  final config = ref.watch(appConfigProvider);
  if (config.isDemoMode || !config.isConfigured) {
    return FakeFinanceRepository();
  }
  return SupabaseFinanceRepository(Supabase.instance.client);
});

final depositQueueProvider = FutureProvider.family<List<Map<String, dynamic>>, String?>((ref, status) async {
  final repo = ref.watch(financeRepositoryProvider);
  return await repo.getDepositQueue(status);
});

final activePaymentDestinationsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final repo = ref.watch(financeRepositoryProvider);
  return await repo.getActivePaymentDestinations();
});

final paymentDestinationsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final repo = ref.watch(financeRepositoryProvider);
  // Active destinations are sufficient for the customer deposit screen.
  return await repo.getActivePaymentDestinations();
});

final settlementBatchesProvider = FutureProvider.family<List<Map<String, dynamic>>, String?>((ref, status) async {
  final repo = ref.watch(financeRepositoryProvider);
  return await repo.getFinanceSettlementBatches(status);
});

final ownerSettlementsProvider = FutureProvider.family<List<Map<String, dynamic>>, String?>((ref, networkId) async {
  final repo = ref.watch(financeRepositoryProvider);
  return await repo.getOwnerSettlements(networkId);
});
