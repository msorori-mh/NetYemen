import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/customer_auth_repository.dart';

final customerAuthRepositoryProvider = Provider<CustomerAuthRepository>((ref) {
  return SupabaseCustomerAuthRepository();
});
