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

final purchaseHistoryProvider = FutureProvider<List<PurchaseOrder>>((ref) async {
  final repo = ref.watch(purchaseRepositoryProvider);
  return await repo.getMyPurchaseOrders();
});

final fulfillmentRecordsProvider = FutureProvider<List<FulfillmentRecord>>((ref) async {
  final repo = ref.watch(purchaseRepositoryProvider);
  return await repo.getMyFulfillmentRecords();
});
