import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/entities.dart';
import 'support_repository.dart';

class SupabaseSupportRepository implements SupportRepository {
  final SupabaseClient client;
  SupabaseSupportRepository(this.client);
  static const fields =
      'id,case_number,case_type,category,priority,subject,description,status,network_id,package_id,network_request_id,assigned_agent_id,resolution,resolution_outcome,due_at,created_at,reopened_count';
  @override
  Future<List<SupportCase>> fetchCases() async =>
      ((await client
                  .from('support_cases')
                  .select(fields)
                  .order('created_at', ascending: false))
              as List)
          .map((e) => SupportCase.fromJson(e))
          .toList();
  @override
  Future<SupportCase> fetchCase(String id) async => SupportCase.fromJson(
    await client.from('support_cases').select(fields).eq('id', id).single(),
  );
  @override
  Future<List<SupportMessage>> fetchMessages(String id) async =>
      ((await client
                  .from('support_messages')
                  .select()
                  .eq('case_id', id)
                  .order('created_at'))
              as List)
          .map((e) => SupportMessage.fromJson(e))
          .toList();
  @override
  Future<List<SupportEvent>> fetchEvents(String id) async =>
      ((await client
                  .from('support_case_events')
                  .select()
                  .eq('case_id', id)
                  .order('created_at'))
              as List)
          .map((e) => SupportEvent.fromJson(e))
          .toList();
  @override
  Future<String> createCase({
    required SupportCaseType type,
    required String category,
    required String priority,
    required String subject,
    required String description,
    String? networkId,
    String? packageId,
    String? requestId,
  }) async {
    final r = await client.rpc(
      'create_support_case',
      params: {
        'p_case_type': type.name,
        'p_category': category,
        'p_priority': priority,
        'p_subject': subject,
        'p_description': description,
        'p_network_id': networkId,
        'p_package_id': packageId,
        'p_network_request_id': requestId,
      },
    );
    return r['id'];
  }

  @override
  Future<void> addMessage(String id, String body) => client.rpc(
    'add_support_message',
    params: {'p_case_id': id, 'p_body': body},
  );
  @override
  Future<void> claim(String id) =>
      client.rpc('claim_support_case', params: {'p_case_id': id});
  @override
  Future<void> updateStatus(
    String id,
    String status, {
    String? resolution,
    String? outcome,
    String? priority,
  }) => client.rpc(
    'update_support_case',
    params: {
      'p_case_id': id,
      'p_status': status,
      'p_resolution': resolution,
      'p_resolution_outcome': outcome,
      'p_priority': priority,
    },
  );
  @override
  Future<void> addNote(String id, String body) => client.rpc(
    'add_support_case_note',
    params: {'p_case_id': id, 'p_body': body},
  );
  @override
  Future<void> reopen(String id, String reason) => client.rpc(
    'reopen_support_case',
    params: {'p_case_id': id, 'p_reason': reason},
  );
}
