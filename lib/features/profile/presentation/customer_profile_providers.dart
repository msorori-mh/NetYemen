import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/customer_session_providers.dart';
import '../data/customer_profile_repository.dart';
import '../domain/customer_profile.dart';

final userProfileProvider = FutureProvider<CustomerProfile?>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;

  final repository = ref.watch(customerProfileRepositoryProvider);
  return repository.fetchMyProfile();
});
