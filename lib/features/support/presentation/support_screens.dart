import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/app_providers.dart';
import '../domain/entities.dart';
import '../domain/support_operation_policy.dart';
import 'support_providers.dart';

const statusAr = {
  'open': 'مفتوحة',
  'assigned': 'مُسندة',
  'in_progress': 'قيد المعالجة',
  'waiting_customer': 'بانتظار العميل',
  'resolved': 'تم الحل',
  'closed': 'مغلقة',
};
const typeAr = {'ticket': 'تذكرة', 'complaint': 'شكوى', 'dispute': 'نزاع'};

class MySupportScreen extends ConsumerWidget {
  const MySupportScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(supportCasesProvider);
    final roles = ref.watch(currentUserRolesProvider).valueOrNull ?? [];
    final staff = roles.any({'support_agent', 'platform_admin'}.contains);
    return Scaffold(
      appBar: AppBar(
        title: const Text('دعمي'),
        actions: [
          if (staff)
            IconButton(
              tooltip: 'قائمة الدعم',
              icon: const Icon(Icons.support_agent),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SupportQueueScreen()),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new-support-case',
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const NewSupportCaseScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('تذكرة جديدة'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(supportCasesProvider),
        child: items.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const _State(
            icon: Icons.error_outline,
            text: 'تعذر تحميل التذاكر. حاول مرة أخرى.',
          ),
          data: (list) => list.isEmpty
              ? const _State(
                  icon: Icons.support_outlined,
                  text: 'لا توجد تذاكر دعم بعد',
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: list.length,
                  itemBuilder: (_, i) => CaseTile(item: list[i]),
                ),
        ),
      ),
    );
  }
}

class SupportQueueScreen extends ConsumerWidget {
  final bool includeClosed;
  final String title;
  const SupportQueueScreen({
    super.key,
    this.includeClosed = false,
    this.title = 'قائمة انتظار الدعم',
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(supportCasesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: items.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const _State(
          icon: Icons.error_outline,
          text: 'تعذر تحميل قائمة الدعم. حاول مرة أخرى.',
        ),
        data: (all) {
          final open = includeClosed
              ? all
              : all
                  .where((e) => !{'resolved', 'closed'}.contains(e.status))
                  .toList();
          return open.isEmpty
              ? const _State(
                  icon: Icons.inbox_outlined,
                  text: 'لا توجد حالات معلقة',
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: open.length,
                  itemBuilder: (_, i) => CaseTile(item: open[i], agent: true),
                );
        },
      ),
    );
  }
}

class CaseTile extends StatelessWidget {
  final SupportCase item;
  final bool agent;
  const CaseTile({super.key, required this.item, this.agent = false});
  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: CircleAvatar(child: Text('#${item.number}')),
          title: Text(item.subject),
          subtitle: Text(
            '${typeAr[item.type.name]} • ${statusAr[item.status]} • ${item.priority}${item.isOverdue ? ' • متأخرة عن SLA' : ''}',
          ),
          trailing: const Icon(Icons.chevron_left),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  SupportCaseScreen(caseId: item.id, agentView: agent),
            ),
          ),
        ),
      );
}

class NewSupportCaseScreen extends ConsumerStatefulWidget {
  const NewSupportCaseScreen({super.key});
  @override
  ConsumerState<NewSupportCaseScreen> createState() => _NewSupportCaseState();
}

class _NewSupportCaseState extends ConsumerState<NewSupportCaseScreen> {
  final form = GlobalKey<FormState>(),
      subject = TextEditingController(),
      description = TextEditingController(),
      network = TextEditingController(),
      package = TextEditingController(),
      request = TextEditingController();
  SupportCaseType type = SupportCaseType.ticket;
  String category = 'service', priority = 'normal';
  bool busy = false;
  @override
  void dispose() {
    for (final c in [subject, description, network, package, request]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('تذكرة جديدة')),
        body: Form(
          key: form,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              DropdownButtonFormField(
                initialValue: type,
                decoration: const InputDecoration(labelText: 'النوع'),
                items: SupportCaseType.values
                    .map(
                      (v) => DropdownMenuItem(
                          value: v, child: Text(typeAr[v.name]!)),
                    )
                    .toList(),
                onChanged: (v) => setState(() => type = v!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField(
                initialValue: category,
                decoration: const InputDecoration(labelText: 'التصنيف'),
                items: [
                  'network',
                  'package',
                  'service',
                  'account',
                  'request',
                  'other',
                ]
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: (v) => setState(() => category = v!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField(
                initialValue: priority,
                decoration: const InputDecoration(labelText: 'الأولوية'),
                items: [
                  'low',
                  'normal',
                  'high',
                  'urgent',
                ]
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: (v) => setState(() => priority = v!),
              ),
              const SizedBox(height: 12),
              _field(subject, 'الموضوع', 3),
              const SizedBox(height: 12),
              _field(description, 'التفاصيل', 3, lines: 5),
              const SizedBox(height: 12),
              _field(network, 'معرّف الشبكة (اختياري)', 0, optional: true),
              const SizedBox(height: 12),
              _field(package, 'معرّف الباقة (اختياري)', 0, optional: true),
              const SizedBox(height: 12),
              _field(request, 'معرّف الطلب (اختياري)', 0, optional: true),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: busy ? null : _submit,
                child: Text(busy ? 'جارٍ الإرسال...' : 'إنشاء التذكرة'),
              ),
            ],
          ),
        ),
      );
  Widget _field(
    TextEditingController c,
    String label,
    int min, {
    int lines = 1,
    bool optional = false,
  }) =>
      TextFormField(
        controller: c,
        maxLines: lines,
        decoration: InputDecoration(labelText: label),
        validator: (v) => optional || ((v?.trim().length ?? 0) >= min)
            ? null
            : 'يرجى إدخال $label',
      );
  Future<void> _submit() async {
    if (!form.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      final id = await ref.read(supportRepositoryProvider).createCase(
            type: type,
            category: category,
            priority: priority,
            subject: subject.text,
            description: description.text,
            networkId: _null(network.text),
            packageId: _null(package.text),
            requestId: _null(request.text),
          );
      if (!mounted) return;
      refreshSupport(ref, null);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => SupportCaseScreen(caseId: id)),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر إنشاء التذكرة. حاول مرة أخرى.')),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String? _null(String v) => v.trim().isEmpty ? null : v.trim();
}

class SupportCaseScreen extends ConsumerWidget {
  final String caseId;
  final bool agentView;
  const SupportCaseScreen({
    super.key,
    required this.caseId,
    this.agentView = false,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(supportCaseProvider(caseId));
    final messages = ref.watch(supportMessagesProvider(caseId));
    final events = ref.watch(supportEventsProvider(caseId));
    return Scaffold(
      appBar: AppBar(
        title: Text(agentView ? 'عرض الحالة للموظف' : 'تفاصيل التذكرة'),
      ),
      body: item.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const _State(
          icon: Icons.error_outline,
          text: 'تعذر تحميل حالة الدعم. حاول مرة أخرى.',
        ),
        data: (c) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              '#${c.number} — ${c.subject}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                Chip(label: Text(typeAr[c.type.name]!)),
                Chip(label: Text(statusAr[c.status]!)),
                Chip(label: Text('الأولوية: ${c.priority}')),
                if (c.isOverdue)
                  const Chip(
                    label: Text('متأخرة عن SLA'),
                    backgroundColor: Color(0xFFFFE0E0),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(c.description),
            if (c.networkId != null) Text('الشبكة: ${c.networkId}'),
            if (c.packageId != null) Text('الباقة: ${c.packageId}'),
            if (c.requestId != null) Text('الطلب: ${c.requestId}'),
            if (c.resolution != null) ...[
              const Divider(),
              Text('الحل: ${c.resolution}'),
            ],
            if (agentView) ...[
              const Divider(),
              Wrap(
                spacing: 8,
                children: [
                  if (c.assignedAgentId == null)
                    OutlinedButton(
                      onPressed: () => _act(
                        context,
                        ref,
                        () => ref.read(supportRepositoryProvider).claim(caseId),
                      ),
                      child: const Text('استلام الحالة'),
                    ),
                  OutlinedButton(
                    onPressed: () => _workflow(context, ref, c),
                    child: const Text('تحديث الحالة'),
                  ),
                  OutlinedButton(
                    onPressed: () => _textAction(
                      context,
                      ref,
                      'ملاحظة داخلية',
                      (v) => ref
                          .read(supportRepositoryProvider)
                          .addNote(caseId, v),
                    ),
                    child: const Text('إضافة ملاحظة'),
                  ),
                ],
              ),
            ],
            if ({'resolved', 'closed'}.contains(c.status) &&
                c.reopenedCount < 3)
              OutlinedButton(
                onPressed: () => _textAction(
                  context,
                  ref,
                  'سبب إعادة الفتح',
                  (v) => ref.read(supportRepositoryProvider).reopen(caseId, v),
                ),
                child: const Text('إعادة فتح الحالة'),
              ),
            const Divider(),
            Text('الرسائل', style: Theme.of(context).textTheme.titleMedium),
            messages.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => const Text('تعذر تحميل الرسائل.'),
              data: (m) => Column(
                children: m
                    .map(
                      (x) => ListTile(
                        leading: const Icon(Icons.chat_bubble_outline),
                        title: Text(x.body),
                        subtitle: Text(x.createdAt.toLocal().toString()),
                      ),
                    )
                    .toList(),
              ),
            ),
            if (c.status != 'closed')
              FilledButton.icon(
                onPressed: () => _textAction(
                  context,
                  ref,
                  'رسالة',
                  (v) =>
                      ref.read(supportRepositoryProvider).addMessage(caseId, v),
                ),
                icon: const Icon(Icons.send),
                label: const Text('إرسال رد'),
              ),
            const Divider(),
            Text('السجل', style: Theme.of(context).textTheme.titleMedium),
            events.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => const Text('تعذر تحميل سجل الحالة.'),
              data: (ev) => Column(
                children: ev
                    .map(
                      (x) => ListTile(
                        dense: true,
                        title: Text(x.eventType),
                        subtitle: Text(
                          '${x.fromStatus ?? ''} ${x.toStatus ?? ''} • ${x.createdAt.toLocal()}',
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _act(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() fn,
  ) async {
    try {
      await fn();
      refreshSupport(ref, caseId);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر تنفيذ العملية. حاول مرة أخرى.')),
        );
      }
    }
  }

  Future<void> _textAction(
    BuildContext context,
    WidgetRef ref,
    String label,
    Future<void> Function(String) fn,
  ) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(label),
        content: TextField(
          controller: c,
          maxLines: 4,
          maxLength: SupportOperationPolicy.maximumActionTextLength,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (!context.mounted) {
      c.dispose();
      return;
    }
    if (ok == true && c.text.trim().isNotEmpty) {
      await _act(context, ref, () => fn(c.text.trim()));
    }
    c.dispose();
  }

  Future<void> _workflow(
    BuildContext context,
    WidgetRef ref,
    SupportCase c,
  ) async {
    String status = c.status == 'open' ? 'assigned' : c.status;
    final resolution = TextEditingController();
    String? outcome;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: const Text('تحديث الحالة'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField(
                initialValue: status,
                items: [
                  'assigned',
                  'in_progress',
                  'waiting_customer',
                  'resolved',
                  'closed',
                ]
                    .map(
                      (v) => DropdownMenuItem(
                        value: v,
                        child: Text(statusAr[v]!),
                      ),
                    )
                    .toList(),
                onChanged: (v) => set(() => status = v!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: resolution,
                decoration: const InputDecoration(
                  labelText: 'الحل (مطلوب للحل/الإغلاق)',
                ),
              ),
              if (c.type == SupportCaseType.dispute)
                DropdownButtonFormField<String>(
                  initialValue: outcome,
                  decoration: const InputDecoration(labelText: 'النتيجة'),
                  items: [
                    'answered',
                    'fixed',
                    'not_reproducible',
                    'not_supported',
                    'refund_recommended',
                  ]
                      .map(
                        (v) => DropdownMenuItem(value: v, child: Text(v)),
                      )
                      .toList(),
                  onChanged: (v) => set(() => outcome = v),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('تحديث'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) {
      resolution.dispose();
      return;
    }
    if (ok == true) {
      final validationMessage = SupportOperationPolicy.validateResolution(
        status,
        resolution.text,
      );
      if (validationMessage != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(validationMessage)));
      } else {
        await _act(
          context,
          ref,
          () => ref.read(supportRepositoryProvider).updateStatus(
                caseId,
                status,
                resolution: SupportOperationPolicy.normalizeActionText(
                  resolution.text,
                ),
                outcome: outcome,
              ),
        );
      }
    }
    resolution.dispose();
  }
}

class _State extends StatelessWidget {
  final IconData icon;
  final String text;
  const _State({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => ListView(
        children: [
          const SizedBox(height: 160),
          Icon(icon, size: 64, color: AppTheme.textMuted),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center),
        ],
      );
}
