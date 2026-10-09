import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config_provider.dart';
import 'fake_finance_repository.dart';
import 'finance_repository.dart';
import 'supabase_finance_repository.dart';

final financeRepositoryProvider = Provider<FinanceRepository>((ref) {
  final config = ref.watch(appConfigProvider);
  if (config.usesDemoData) {
    return FakeFinanceRepository();
  }
  return SupabaseFinanceRepository(Supabase.instance.client);
});

final activePaymentDestinationsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final repo = ref.watch(financeRepositoryProvider);
  return await repo.getActivePaymentDestinations();
});
