import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CustomerProfileUpdate {
  final String fullName;
  final String governorate;
  final String city;

  const CustomerProfileUpdate({
    required this.fullName,
    required this.governorate,
    required this.city,
  });

  Map<String, String> toJson() => {
        'full_name': fullName.trim(),
        'default_governorate': governorate.trim(),
        'default_city': city.trim(),
      };
}

abstract class CustomerProfileRepository {
  Future<void> updateMyProfile(CustomerProfileUpdate update);
}

class SupabaseCustomerProfileRepository implements CustomerProfileRepository {
  final SupabaseClient _client;

  const SupabaseCustomerProfileRepository(this._client);

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
