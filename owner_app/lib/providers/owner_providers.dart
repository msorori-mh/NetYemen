// lib/providers/owner_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/owned_network_model.dart';
import '../services/owner_supabase_service.dart';

// Service
final ownerServiceProvider = Provider<OwnerSupabaseService>((ref) {
  return OwnerSupabaseService();
});

// Auth
final authStateProvider = StreamProvider<AuthState>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange;
});

final currentUserProvider = Provider<User?>((ref) {
  // Watch auth state to update automatically when switching accounts
  final authState = ref.watch(authStateProvider).value;
  return authState?.session?.user ?? Supabase.instance.client.auth.currentUser;
});

final hasNetworkOwnerRoleProvider = FutureProvider<bool>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return false;
  
  final service = ref.watch(ownerServiceProvider);
  return await service.hasPlatformRole('network_owner');
});

// Owned networks (حاجز الدور + محتوى لوحة التحكم)
final ownedNetworksProvider = FutureProvider<List<OwnedNetwork>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];

  final service = ref.watch(ownerServiceProvider);
  return await service.getOwnedNetworks();
});

// PIN Gate Provider
final hasAccountPinProvider = FutureProvider<bool>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return false;
  
  final service = ref.watch(ownerServiceProvider);
  return await service.hasAccountPin();
});

// رقم التبويب المحدد
final selectedTabProvider = StateProvider<int>((ref) => 0);
