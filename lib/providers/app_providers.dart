// lib/providers/app_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../features/network_discovery/presentation/network_discovery_providers.dart';
export '../features/network_discovery/presentation/network_discovery_providers.dart' show appConfigProvider;
import '../models/user_model.dart';
import '../models/network_model.dart';
import '../services/supabase_service.dart';

// Service
final supabaseServiceProvider = Provider<SupabaseService>((ref) {
  return SupabaseService();
});

// Auth
final authStateProvider = StreamProvider<AuthState>((ref) {
  final config = ref.watch(appConfigProvider);
  if (config.isDemoMode || !config.isConfigured) {
    return const Stream<AuthState>.empty();
  }
  return Supabase.instance.client.auth.onAuthStateChange;
});

final currentUserProvider = Provider<User?>((ref) {
  final config = ref.watch(appConfigProvider);
  if (config.isDemoMode || !config.isConfigured) return null;

  final authAsync = ref.watch(authStateProvider);
  final client = Supabase.instance.client;
  return authAsync.when(
    data: (state) => state.session?.user ?? client.auth.currentUser,
    loading: () => client.auth.currentUser,
    error: (_, __) => client.auth.currentUser,
  );
});

/// Current user's platform roles. In demo mode returns [platform_admin] so the
/// admin section remains reachable for preview; otherwise queries Supabase.
final currentUserRolesProvider = FutureProvider<List<String>>((ref) async {
  final config = ref.watch(appConfigProvider);
  if (config.isDemoMode) {
    return const ['platform_admin'];
  }
  if (!config.isConfigured) {
    return const [];
  }

  final user = ref.watch(currentUserProvider);
  if (user == null) return const [];

  final response = await Supabase.instance.client
      .from('user_roles')
      .select('role')
      .eq('user_id', user.id);

  return (response as List)
      .map((json) => (json as Map<String, dynamic>)['role'] as String?)
      .whereType<String>()
      .toList();
});

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
