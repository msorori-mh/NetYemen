import '../domain/entities.dart';
import 'support_repository.dart';

class FakeSupportRepository implements SupportRepository {
  final List<SupportCase> cases = [];
  final Map<String, List<SupportMessage>> messages = {};
  @override
  Future<List<SupportCase>> fetchCases() async => List.unmodifiable(cases);
  @override
  Future<SupportCase> fetchCase(String id) async =>
      cases.firstWhere((e) => e.id == id);
  @override
  Future<List<SupportMessage>> fetchMessages(String id) async =>
      messages[id] ?? [];
  @override
  Future<List<SupportEvent>> fetchEvents(String id) async => [];
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
    final id = 'case-${cases.length + 1}';
    cases.add(
      SupportCase(
        id: id,
        number: 1000 + cases.length,
        type: type,
        category: category,
        priority: priority,
        subject: subject,
        description: description,
        status: 'open',
        networkId: networkId,
        packageId: packageId,
        requestId: requestId,
        dueAt: DateTime.now().add(const Duration(hours: 48)),
        createdAt: DateTime.now(),
      ),
    );
    return id;
  }

  @override
  Future<void> addMessage(String id, String body) async =>
      messages.putIfAbsent(id, () => []).add(
            SupportMessage(
              id: 'm-${DateTime.now().microsecondsSinceEpoch}',
              authorUserId: 'demo',
              body: body,
              createdAt: DateTime.now(),
            ),
          );
  @override
  Future<void> claim(String id) async => _replace(id, status: 'assigned');
  @override
  Future<void> updateStatus(
    String id,
    String status, {
    String? resolution,
    String? outcome,
    String? priority,
  }) async =>
      _replace(id, status: status, resolution: resolution, outcome: outcome);
  @override
  Future<void> addNote(String id, String body) async {}
  @override
  Future<void> reopen(String id, String reason) async =>
      _replace(id, status: 'open');
  void _replace(
    String id, {
    required String status,
    String? resolution,
    String? outcome,
  }) {
    final i = cases.indexWhere((e) => e.id == id);
    final c = cases[i];
    cases[i] = SupportCase(
      id: c.id,
      number: c.number,
      type: c.type,
      category: c.category,
      priority: c.priority,
      subject: c.subject,
      description: c.description,
      status: status,
      dueAt: c.dueAt,
      createdAt: c.createdAt,
      resolution: resolution ?? c.resolution,
      resolutionOutcome: outcome ?? c.resolutionOutcome,
    );
  }
}
