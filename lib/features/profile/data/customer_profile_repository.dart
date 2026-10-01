import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/customer_profile.dart';

abstract class CustomerProfileRepository {
  Future<CustomerProfile?> fetchMyProfile();

  Future<void> updateMyProfile(CustomerProfileUpdate update);
}

class SupabaseCustomerProfileRepository implements CustomerProfileRepository {
  final SupabaseClient _client;

  const SupabaseCustomerProfileRepository(this._client);

  @override
  Future<CustomerProfile?> fetchMyProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('AUTH_REQUIRED');

    final response = await _client
        .from('profiles')
        .select(
          'id, full_name, account_status, default_governorate, default_city, created_at',
        )
        .eq('id', user.id)
        .maybeSingle();
    if (response == null) return null;

    return CustomerProfile.fromJson(response);
  }

  @override
  Future<void> updateMyProfile(CustomerProfileUpdate update) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('AUTH_REQUIRED');

    await _client.from('profiles').update(update.toJson()).eq('id', userId);
  }
}

final customerProfileRepositoryProvider = Provider<CustomerProfileRepository>((
  ref,
) {
  return SupabaseCustomerProfileRepository(Supabase.instance.client);
});
