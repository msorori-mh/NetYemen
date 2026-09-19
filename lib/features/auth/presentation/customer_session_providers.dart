import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config_provider.dart';

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
