import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/entities.dart';
import 'admin_common_widgets.dart';
import 'admin_providers.dart';

class AdminUsersScreen extends ConsumerWidget {
  const AdminUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(adminUsersProvider);
    final onboardingAsync = ref.watch(adminTestOnboardingProvider);

    Future<void> refreshAll() async {
      await Future.wait([
        ref.read(adminUsersProvider.notifier).refresh(),
        ref.read(adminTestOnboardingProvider.notifier).refresh(),
      ]);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('المستخدمين'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: refreshAll,
          ),
        ],
      ),
      body: usersAsync.when(
        data: (users) => _UsersBody(
          users: users,
          onboardingAsync: onboardingAsync,
          onRefresh: refreshAll,
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AdminErrorState(
          message: 'تعذر تحميل المستخدمين. حاول مرة أخرى.',
          onRetry: () => ref.read(adminUsersProvider.notifier).refresh(),
        ),
      ),
    );
  }
}

class _UsersBody extends StatelessWidget {
  final List<AdminUser> users;
  final AsyncValue<List<AdminTestOnboardingApplication>> onboardingAsync;
  final Future<void> Function() onRefresh;

  const _UsersBody({
    required this.users,
    required this.onboardingAsync,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _TestOnboardingSection(applicationsAsync: onboardingAsync),
          const SizedBox(height: 12),
          if (users.isEmpty)
            const AdminEmptyState(
              title: 'لا يوجد مستخدمين',
              subtitle: 'لم يتم العثور على مستخدمين في النظام',
            )
          else
            ...users.map((user) => _UserCard(user: user)),
        ],
      ),
    );
  }
}

class _TestOnboardingSection extends ConsumerWidget {
  final AsyncValue<List<AdminTestOnboardingApplication>> applicationsAsync;

  const _TestOnboardingSection({required this.applicationsAsync});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return applicationsAsync.when(
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: LinearProgressIndicator(),
        ),
      ),
      error: (_, __) => Card(
        child: ListTile(
          leading: const Icon(Icons.error_outline, color: AppTheme.error),
          title: const Text('تعذر تحميل طلبات التسجيل التجريبي'),
          trailing: IconButton(
            tooltip: 'إعادة المحاولة',
            onPressed: () =>
                ref.read(adminTestOnboardingProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh),
          ),
        ),
      ),
      data: (applications) => Card(
        child: ExpansionTile(
          key: const Key('test-onboarding-section'),
          initiallyExpanded: false,
          leading: const Icon(Icons.fact_check_outlined),
          title: const Text('طلبات التسجيل التجريبي'),
          subtitle: Text(
            applications.isEmpty
                ? 'لا توجد طلبات معلّقة'
                : '${applications.length} طلب بانتظار قرار المدير',
          ),
          children: applications.isEmpty
              ? const [
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Text('جميع طلبات المختبرين تمت مراجعتها.'),
                  ),
                ]
              : applications
                  .map(
                    (application) => _TestOnboardingCard(
                      application: application,
                    ),
                  )
                  .toList(),
        ),
      ),
    );
  }
}

class _TestOnboardingCard extends ConsumerWidget {
  final AdminTestOnboardingApplication application;

  const _TestOnboardingCard({required this.application});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                application.displayName,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              SelectableText(
                'مرجع الطلب: ${application.id}',
                key: Key('test-onboarding-reference-${application.id}'),
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'النوع المطلوب: ${application.requestedAccountTypeLabel}',
              ),
              Text(
                  'الموقع المعلن: ${application.governorate} — ${application.city}'),
              if (application.requestedAccountType == 'network_owner')
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'الموافقة تفعّل الحساب وتمنح دور صاحب الشبكة، لكنها لا تنشئ شبكة تلقائياً.',
                    style: TextStyle(
                      color: AppTheme.warning,
                      fontSize: 12,
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.icon(
                    key: Key('approve-test-onboarding-${application.id}'),
                    onPressed: () => _review(context, ref, approve: true),
                    icon: const Icon(Icons.check),
                    label: const Text('موافقة'),
                  ),
                  OutlinedButton.icon(
                    key: Key('reject-test-onboarding-${application.id}'),
                    onPressed: () => _review(context, ref, approve: false),
                    icon: const Icon(Icons.close),
                    label: const Text('رفض'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _review(
    BuildContext context,
    WidgetRef ref, {
    required bool approve,
  }) async {
    var reason = '';
    final decision = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(approve ? 'اعتماد الحساب التجريبي' : 'رفض الحساب التجريبي'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              approve
                  ? 'سيتم تفعيل حساب ${application.displayName}. هذا اعتماد اختباري إداري وليس تحققاً برسالة هاتف.'
                  : 'سيتم رفض الطلب وتعليق الحساب. اكتب سبباً واضحاً للمراجعة.',
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('test-onboarding-review-reason'),
              maxLength: 500,
              onChanged: (value) => reason = value,
              decoration: InputDecoration(
                labelText: approve ? 'ملاحظة اختيارية' : 'سبب الرفض',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              if (!approve && reason.trim().isEmpty) return;
              Navigator.of(dialogContext).pop(true);
            },
            child: Text(approve ? 'اعتماد' : 'رفض الطلب'),
          ),
        ],
      ),
    );
    if (decision != true || !context.mounted) return;
    final trimmedReason = reason.trim();
    final messenger = ScaffoldMessenger.of(context);

    try {
      await ref.read(adminTestOnboardingProvider.notifier).review(
            applicationId: application.id,
            decision: approve ? 'approve' : 'reject',
            reason: trimmedReason.isEmpty ? null : trimmedReason,
          );
      if (messenger.mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              approve ? 'تم اعتماد الحساب التجريبي' : 'تم رفض الحساب التجريبي',
            ),
          ),
        );
      }
    } catch (_) {
      await ref.read(adminTestOnboardingProvider.notifier).refresh();
      if (messenger.mounted) {
        messenger.showSnackBar(
          const SnackBar(
              content: Text('تعذر حفظ قرار المراجعة. حاول مرة أخرى.')),
        );
      }
    }
  }
}

class _UserCard extends ConsumerWidget {
  final AdminUser user;

  const _UserCard({required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                  child: const Icon(Icons.person, color: AppTheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.displayName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'الحالة: ${_accountStatusLabel(user.accountStatus)}',
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'إدارة المستخدم',
                  onSelected: (action) {
                    if (action == 'roles') {
                      _manageRoles(context, ref);
                    } else if (action == 'status') {
                      _changeStatus(context, ref);
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'roles',
                      child: Text('إدارة الأدوار الإدارية'),
                    ),
                    PopupMenuItem(
                      value: 'status',
                      child: Text(
                        user.accountStatus == 'active'
                            ? 'تعليق الحساب'
                            : 'تنشيط الحساب',
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: user.roles
                  .map(
                    (role) => AdminStatusChip(
                      label: _roleLabel(role),
                      color: _roleColor(role),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  String _accountStatusLabel(String status) {
    switch (status) {
      case 'active':
        return 'نشط';
      case 'suspended':
        return 'معلّق';
      case 'pending_verification':
        return 'في انتظار التوثيق';
      case 'anonymized':
        return 'مجهول';
      default:
        return status;
    }
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'customer':
        return 'عميل';
      case 'network_owner':
        return 'مالك شبكة';
      case 'network_operator':
        return 'مشغّل شبكة';
      case 'finance_officer':
        return 'مسؤول مالي';
      case 'support_agent':
        return 'وكيل دعم';
      case 'platform_admin':
        return 'مدير المنصة';
      case 'system_auditor':
        return 'مدقق نظام';
      default:
        return role;
    }
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'platform_admin':
        return AppTheme.primary;
      case 'support_agent':
        return AppTheme.info;
      case 'system_auditor':
        return AppTheme.accent;
      case 'network_owner':
        return AppTheme.success;
      case 'network_operator':
        return AppTheme.warning;
      case 'finance_officer':
        return AppTheme.accentDark;
      default:
        return AppTheme.textSecondary;
    }
  }

  Future<void> _manageRoles(BuildContext context, WidgetRef ref) async {
    const roleLabels = <String, String>{
      'platform_admin': 'مدير المنصة',
      'finance_officer': 'مسؤول مالي',
      'support_agent': 'وكيل دعم',
      'system_auditor': 'مدقق نظام',
    };
    final selected = <String>{
      for (final role in user.roles)
        if (roleLabels.containsKey(role)) role,
    };

    final result = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('الأدوار الإدارية — ${user.displayName}'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final entry in roleLabels.entries)
                  CheckboxListTile(
                    value: selected.contains(entry.key),
                    title: Text(entry.value),
                    onChanged: (enabled) => setState(() {
                      if (enabled == true) {
                        selected.add(entry.key);
                      } else {
                        selected.remove(entry.key);
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(Set.of(selected)),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !context.mounted) return;

    try {
      await ref.read(adminUsersProvider.notifier).replacePlatformRoles(
            userId: user.id,
            roles: result,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تحديث الأدوار الإدارية')),
        );
      }
    } catch (_) {
      await ref.read(adminUsersProvider.notifier).refresh();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر تحديث الأدوار. حاول مرة أخرى.')),
        );
      }
    }
  }

  Future<void> _changeStatus(BuildContext context, WidgetRef ref) async {
    final nextStatus = user.accountStatus == 'active' ? 'suspended' : 'active';
    final actionLabel = nextStatus == 'active' ? 'تنشيط' : 'تعليق';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$actionLabel الحساب'),
        content: Text('هل تريد $actionLabel حساب “${user.displayName}”؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(adminUsersProvider.notifier).setAccountStatus(
            userId: user.id,
            status: nextStatus,
            reason: 'Admin console account lifecycle update',
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم $actionLabel الحساب')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر $actionLabel الحساب. حاول مرة أخرى.')),
        );
      }
    }
  }
}
