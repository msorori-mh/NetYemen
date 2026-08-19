// lib/features/purchase/presentation/purchase_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../providers/app_providers.dart';
import '../data/purchase_repository.dart';
import '../data/supabase_purchase_repository.dart';
import '../data/fake_purchase_repository.dart';
import '../domain/entities.dart';

final purchaseRepositoryProvider = Provider<PurchaseRepository>((ref) {
  final config = ref.watch(appConfigProvider);
  if (config.isDemoMode || !config.isConfigured) {
    return FakePurchaseRepository();
  }
  return SupabasePurchaseRepository(Supabase.instance.client);
});

final purchaseHistoryProvider = FutureProvider<List<PurchaseOrder>>((
  ref,
) async {
  final repo = ref.watch(purchaseRepositoryProvider);
  return await repo.getMyPurchaseOrders();
});

final fulfillmentRecordsProvider = FutureProvider<List<FulfillmentRecord>>((
  ref,
) async {
  final repo = ref.watch(purchaseRepositoryProvider);
  return await repo.getMyFulfillmentRecords();
});

final purchaseDetailProvider = FutureProvider.family<PurchaseOrder?, String>((
  ref,
  purchaseId,
) async {
  final repo = ref.watch(purchaseRepositoryProvider);
  final orders = await repo.getMyPurchaseOrders();
  try {
    return orders.firstWhere((o) => o.id == purchaseId);
  } on StateError catch (_) {
    return null;
  }
});

class CardRevealNotifier extends AsyncNotifier<CardRevealResult?> {
  @override
  Future<CardRevealResult?> build() async => null;

  Future<void> reveal(String purchaseId) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(purchaseRepositoryProvider);
      return await repo.revealPurchaseCardSecret(purchaseId);
    });
  }

  Future<void> reset() async => state = const AsyncValue.data(null);
}

final cardRevealNotifierProvider =
    AsyncNotifierProvider<CardRevealNotifier, CardRevealResult?>(
      CardRevealNotifier.new,
    );
