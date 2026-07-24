// lib/providers/app_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';
import '../models/network_model.dart';
import '../services/supabase_service.dart';

// Service
final supabaseServiceProvider = Provider<SupabaseService>((ref) {
  return SupabaseService();
});

// Auth
final authStateProvider = StreamProvider<AuthState>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange;
});

final currentUserProvider = Provider<User?>((ref) {
  return Supabase.instance.client.auth.currentUser;
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

// Purchases
final userPurchasesProvider = FutureProvider<List<Purchase>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];

  final service = ref.watch(supabaseServiceProvider);
  return await service.getUserPurchases(user.id);
});

// Wallet
final walletTransactionsProvider = FutureProvider<List<dynamic>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];

  final service = ref.watch(supabaseServiceProvider);
  return await service.getWalletTransactions(user.id);
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
