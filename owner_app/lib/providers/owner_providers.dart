// lib/providers/owner_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/owned_network_model.dart';
import '../services/owner_supabase_service.dart';
import '../utils/pin_lock_policy.dart';

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

// هل قفل رمز الدخول مفتوح لهذا المستخدم على هذا الجهاز؟
//
// يعتمد على علامة الثقة ووقت آخر نشاط المحفوظَين في SharedPreferences: إغلاق
// التطبيق وإعادة فتحه بعد أكثر من 15 دقيقة خمول يطلب الرمز من جديد. أي خطأ
// في القراءة يعني "مقفل".
final pinTrustedProvider = FutureProvider<bool>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return false;
  return PinLockStore.isUnlocked(user.id);
});

// رقم التبويب المحدد
final selectedTabProvider = StateProvider<int>((ref) => 0);
