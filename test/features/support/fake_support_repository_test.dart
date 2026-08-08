import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/features/support/data/fake_support_repository.dart';
import 'package:netyemen/features/support/domain/entities.dart';

void main() {
  test('supports create, reply, claim, resolution and reopen lifecycle',
      () async {
    final repo = FakeSupportRepository();
    final id = await repo.createCase(
        type: SupportCaseType.complaint,
        category: 'service',
        priority: 'high',
        subject: 'ضعف الخدمة',
        description: 'الخدمة ضعيفة منذ يومين');
    expect((await repo.fetchCases()).single.status, 'open');
    await repo.addMessage(id, 'تفاصيل إضافية');
    expect(await repo.fetchMessages(id), hasLength(1));
    await repo.claim(id);
    expect((await repo.fetchCase(id)).status, 'assigned');
    await repo.updateStatus(id, 'resolved',
        resolution: 'تم الحل', outcome: 'fixed');
    expect((await repo.fetchCase(id)).resolution, 'تم الحل');
    await repo.reopen(id, 'تكررت المشكلة');
    expect((await repo.fetchCase(id)).status, 'open');
  });
  test('SLA overdue excludes resolved cases', () {
    final now = DateTime.now();
    final open = SupportCase(
        id: '1',
        number: 1,
        type: SupportCaseType.ticket,
        category: 'service',
        priority: 'urgent',
        subject: 'x',
        description: 'xxx',
        status: 'open',
        dueAt: now.subtract(const Duration(minutes: 1)),
        createdAt: now);
    final resolved = SupportCase(
        id: '2',
        number: 2,
        type: SupportCaseType.dispute,
        category: 'network',
        priority: 'high',
        subject: 'x',
        description: 'xxx',
        status: 'resolved',
        dueAt: now.subtract(const Duration(minutes: 1)),
        createdAt: now,
        resolution: 'done');
    expect(open.isOverdue, isTrue);
    expect(resolved.isOverdue, isFalse);
  });
}
