import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../providers/app_providers.dart';
import '../data/admin_auth_repository.dart';

final adminAuthRepositoryProvider = Provider<AdminAuthRepository>((ref) {
  final config = ref.watch(appConfigProvider);
  if (!config.isConfigured) return const DisabledAdminAuthRepository();
  return SupabaseAdminAuthRepository(Supabase.instance.client);
});
