import '../domain/entities.dart';

abstract class SupportRepository {
  Future<List<SupportCase>> fetchCases();
  Future<SupportCase> fetchCase(String id);
  Future<List<SupportMessage>> fetchMessages(String id);
  Future<List<SupportEvent>> fetchEvents(String id);
  Future<String> createCase({
    required SupportCaseType type,
    required String category,
    required String priority,
    required String subject,
    required String description,
    String? networkId,
    String? packageId,
    String? requestId,
  });
  Future<void> addMessage(String id, String body);
  Future<void> claim(String id);
  Future<void> updateStatus(
    String id,
    String status, {
    String? resolution,
    String? outcome,
    String? priority,
  });
  Future<void> addNote(String id, String body);
  Future<void> reopen(String id, String reason);
}
