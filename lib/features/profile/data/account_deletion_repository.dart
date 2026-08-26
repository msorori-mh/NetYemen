import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AccountDeletionReceipt {
  final String requestId;
  final DateTime scheduledFor;
  final bool idempotent;

  const AccountDeletionReceipt({
    required this.requestId,
    required this.scheduledFor,
    required this.idempotent,
  });

  factory AccountDeletionReceipt.fromJson(Map<String, dynamic> json) {
    return AccountDeletionReceipt(
      requestId: json['request_id'] as String,
      scheduledFor: DateTime.parse(json['scheduled_for'] as String),
      idempotent: json['idempotent'] as bool? ?? false,
    );
  }
}

abstract class AccountDeletionRepository {
  Future<AccountDeletionReceipt> requestDeletion({String? reason});
}

class SupabaseAccountDeletionRepository implements AccountDeletionRepository {
  final SupabaseClient _client;

  const SupabaseAccountDeletionRepository(this._client);

  @override
  Future<AccountDeletionReceipt> requestDeletion({String? reason}) async {
    final response = await _client.rpc(
      'request_my_account_deletion',
      params: {'p_reason': reason},
    );
    return AccountDeletionReceipt.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
  }
}

final accountDeletionRepositoryProvider = Provider<AccountDeletionRepository>((
  ref,
) {
  return SupabaseAccountDeletionRepository(Supabase.instance.client);
});
