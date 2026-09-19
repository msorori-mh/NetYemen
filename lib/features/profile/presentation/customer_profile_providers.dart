import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/supabase_service_provider.dart';
import '../../../models/user_model.dart';
import '../../auth/presentation/customer_session_providers.dart';

final userProfileProvider = FutureProvider<AppUser?>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;

  final service = ref.watch(supabaseServiceProvider);
  return service.getUserProfile(user.id);
});
