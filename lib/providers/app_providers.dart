// lib/providers/app_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';
import '../models/network_model.dart';
import '../models/purchase_model.dart';
import '../models/wallet_model.dart';
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

final networkPricesProvider =
    FutureProvider.family<List<NetworkPrice>, String>((ref, networkId) async {
  final service = ref.watch(supabaseServiceProvider);
  return await service.getNetworkPrices(networkId);
});

// Purchases
final userPurchasesProvider = FutureProvider<List<Purchase>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];

  final service = ref.watch(supabaseServiceProvider);
  return await service.getUserPurchases(user.id);
});

// Wallet
final walletBalanceProvider = FutureProvider<int>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return 0;

  final service = ref.watch(supabaseServiceProvider);
  return await service.getWalletBalance(user.id);
});

final walletLedgerProvider = FutureProvider<List<WalletLedgerEntry>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];

  final service = ref.watch(supabaseServiceProvider);
  return await service.getWalletLedger(user.id);
});

final bankAccountsProvider = FutureProvider<List<BankAccount>>((ref) async {
  final service = ref.watch(supabaseServiceProvider);
  return await service.getBankAccounts();
});

// UI State
final selectedTabProvider = StateProvider<int>((ref) => 0);
