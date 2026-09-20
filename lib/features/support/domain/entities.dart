enum SupportCaseType { ticket, complaint, dispute }

class SupportCase {
  final String id;
  final int number;
  final SupportCaseType type;
  final String category;
  final String priority;
  final String subject;
  final String description;
  final String status;
  final String? networkId;
  final String? packageId;
  final String? requestId;
  final String? assignedAgentId;
  final String? resolution;
  final String? resolutionOutcome;
  final DateTime dueAt;
  final DateTime createdAt;
  final int reopenedCount;

  const SupportCase({
    required this.id,
    required this.number,
    required this.type,
    required this.category,
    required this.priority,
    required this.subject,
    required this.description,
    required this.status,
    this.networkId,
    this.packageId,
    this.requestId,
    this.assignedAgentId,
    this.resolution,
    this.resolutionOutcome,
    required this.dueAt,
    required this.createdAt,
    this.reopenedCount = 0,
  });

  factory SupportCase.fromJson(Map<String, dynamic> j) => SupportCase(
        id: j['id'] as String,
        number: (j['case_number'] as num).toInt(),
        type: SupportCaseType.values.byName(j['case_type'] as String),
        category: j['category'] as String,
        priority: j['priority'] as String,
        subject: j['subject'] as String,
        description: j['description'] as String,
        status: j['status'] as String,
        networkId: j['network_id'] as String?,
        packageId: j['package_id'] as String?,
        requestId: j['network_request_id'] as String?,
        assignedAgentId: j['assigned_agent_id'] as String?,
        resolution: j['resolution'] as String?,
        resolutionOutcome: j['resolution_outcome'] as String?,
        dueAt: DateTime.parse(j['due_at'] as String),
        createdAt: DateTime.parse(j['created_at'] as String),
        reopenedCount: (j['reopened_count'] as num?)?.toInt() ?? 0,
      );

  bool get isOverdue =>
      !{'resolved', 'closed'}.contains(status) &&
      dueAt.isBefore(DateTime.now());
}

class SupportMessage {
  final String id, authorUserId, body;
  final DateTime createdAt;
  const SupportMessage({
    required this.id,
    required this.authorUserId,
    required this.body,
    required this.createdAt,
  });
  factory SupportMessage.fromJson(Map<String, dynamic> j) => SupportMessage(
        id: j['id'],
        authorUserId: j['author_user_id'],
        body: j['body'],
        createdAt: DateTime.parse(j['created_at']),
      );
}

class SupportEvent {
  final String eventType;
  final String? fromStatus, toStatus;
  final DateTime createdAt;
  const SupportEvent({
    required this.eventType,
    this.fromStatus,
    this.toStatus,
    required this.createdAt,
  });
  factory SupportEvent.fromJson(Map<String, dynamic> j) => SupportEvent(
        eventType: j['event_type'],
        fromStatus: j['from_status'],
        toStatus: j['to_status'],
        createdAt: DateTime.parse(j['created_at']),
      );
}
