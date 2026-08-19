import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../network_discovery/presentation/network_discovery_providers.dart';
import '../data/fake_support_repository.dart';
import '../data/support_repository.dart';
import '../data/supabase_support_repository.dart';
import '../domain/entities.dart';

final supportRepositoryProvider = Provider<SupportRepository>((ref) {
  final c = ref.watch(appConfigProvider);
  return c.isDemoMode || !c.isConfigured
      ? FakeSupportRepository()
      : SupabaseSupportRepository(Supabase.instance.client);
});
final supportCasesProvider = FutureProvider<List<SupportCase>>(
  (ref) => ref.watch(supportRepositoryProvider).fetchCases(),
);
final supportCaseProvider = FutureProvider.family<SupportCase, String>(
  (ref, id) => ref.watch(supportRepositoryProvider).fetchCase(id),
);
final supportMessagesProvider =
    FutureProvider.family<List<SupportMessage>, String>(
  (ref, id) => ref.watch(supportRepositoryProvider).fetchMessages(id),
);
final supportEventsProvider = FutureProvider.family<List<SupportEvent>, String>(
  (ref, id) => ref.watch(supportRepositoryProvider).fetchEvents(id),
);
void refreshSupport(WidgetRef ref, String? id) {
  ref.invalidate(supportCasesProvider);
  if (id != null) {
    ref.invalidate(supportCaseProvider(id));
    ref.invalidate(supportMessagesProvider(id));
    ref.invalidate(supportEventsProvider(id));
  }
}
