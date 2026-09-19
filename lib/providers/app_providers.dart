// lib/providers/app_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/providers/supabase_service_provider.dart';
import '../features/auth/presentation/customer_session_providers.dart';
export '../core/config/app_config_provider.dart' show appConfigProvider;
export '../core/providers/supabase_service_provider.dart'
    show supabaseServiceProvider;
export '../features/auth/presentation/customer_session_providers.dart'
    show authStateProvider, currentUserProvider, currentUserRolesProvider;
import '../models/user_model.dart';
import '../models/network_model.dart';

// User Profile
final userProfileProvider = FutureProvider<AppUser?>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;

  final service = ref.watch(supabaseServiceProvider);
  return await service.getUserProfile(user.id);
});

// Networks
final networksProvider = FutureProvider<List<Network>>((ref) async {
  final service = ref.watch(supabaseServiceProvider);
  return await service.getNetworks();
});

final networksSearchQueryProvider = StateProvider<String>((ref) => '');

// Purchases (V1 commerce schema)
final userPurchasesProvider = FutureProvider<List<dynamic>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];

  final service = ref.watch(supabaseServiceProvider);
  return await service.getMyPurchaseOrders();
});

// Wallet (V1 commerce schema)
final walletTransactionsProvider = FutureProvider<List<dynamic>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];

  final service = ref.watch(supabaseServiceProvider);
  return await service.getMyDepositRequests();
});

final walletBalanceProvider = Provider<int>((ref) {
  final userAsync = ref.watch(userProfileProvider);
  return userAsync.when(
    data: (user) => user?.walletBalance ?? 0,
    loading: () => 0,
    error: (_, __) => 0,
  );
});

// UI State
final selectedTabProvider = StateProvider<int>((ref) => 0);
final selectedDenominationProvider = StateProvider<int?>((ref) => null);
