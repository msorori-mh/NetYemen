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

    return Scaffold(
      appBar: AppBar(
        title: const Text('المستخدمين'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(adminUsersProvider.notifier).refresh(),
          ),
        ],
      ),
      body: usersAsync.when(
        data: (users) => _UsersBody(
          users: users,
          onRefresh: () => ref.read(adminUsersProvider.notifier).refresh(),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AdminErrorState(
          message: 'حدث خطأ في تحميل المستخدمين: $e',
          onRetry: () => ref.read(adminUsersProvider.notifier).refresh(),
        ),
      ),
    );
  }
}

class _UsersBody extends StatelessWidget {
  final List<AdminUser> users;
  final Future<void> Function() onRefresh;

  const _UsersBody({required this.users, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: users.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 120),
                AdminEmptyState(
                  title: 'لا يوجد مستخدمين',
                  subtitle: 'لم يتم العثور على مستخدمين في النظام',
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: users.length,
              itemBuilder: (_, i) => _UserCard(user: users[i]),
            ),
    );
  }
}

class _UserCard extends StatelessWidget {
  final AdminUser user;

  const _UserCard({required this.user});

  @override
  Widget build(BuildContext context) {
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
}
