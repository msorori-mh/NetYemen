import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/supabase_service.dart';

/// Transitional provider for the legacy Supabase service facade.
///
/// New feature repositories should depend on their own typed abstractions. The
/// shared provider remains here while the remaining legacy screens migrate.
final supabaseServiceProvider = Provider<SupabaseService>((ref) {
  return SupabaseService();
});
