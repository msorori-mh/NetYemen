// lib/features/wallet/presentation/wallet_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../providers/app_providers.dart';
import '../data/wallet_repository.dart';
import '../data/supabase_wallet_repository.dart';
import '../data/fake_wallet_repository.dart';
import '../domain/entities.dart';

final walletRepositoryProvider = Provider<WalletRepository>((ref) {
  final config = ref.watch(appConfigProvider);
  if (config.isDemoMode || !config.isConfigured) {
    return FakeWalletRepository();
  }
  return SupabaseWalletRepository(Supabase.instance.client);
});

final walletSummaryProvider = FutureProvider<WalletSummary>((ref) async {
  final repo = ref.watch(walletRepositoryProvider);
  return await repo.getMyWalletSummary();
});

final depositHistoryProvider = FutureProvider<List<DepositRequest>>((ref) async {
  final repo = ref.watch(walletRepositoryProvider);
  return await repo.getMyDepositRequests();
});

final depositChannelsProvider = FutureProvider<List<DepositChannel>>((ref) async {
  final repo = ref.watch(walletRepositoryProvider);
  return await repo.getActiveDepositChannels();
});
