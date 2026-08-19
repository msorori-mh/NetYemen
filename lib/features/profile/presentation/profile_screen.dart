import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/app_providers.dart';
import '../../../utils/constants.dart';
import '../../../screens/auth/login_screen.dart';
import '../../admin/presentation/admin_dashboard_screen.dart';
import '../../notifications/presentation/notification_center_screen.dart';
import '../../notifications/presentation/notification_preferences_screen.dart';
import '../../notifications/presentation/fcm_token_service.dart';
import '../../network_requests/presentation/my_requests_screen.dart';
import '../../packages/presentation/owner_dashboard_screen.dart';
import '../../support/presentation/support_screens.dart';
import '../../wallet/presentation/deposit_history_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('الحساب')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 48,
                  backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                  child: const Icon(
                    Icons.person,
                    size: 48,
                    color: AppTheme.primary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  user != null ? 'مستخدم مسجل' : 'غير مسجل',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (user != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    user.email ?? user.phone ?? '---',
                    style: const TextStyle(color: AppTheme.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 32),
          if (config.isDemoMode)
            Card(
              color: AppTheme.warning.withValues(alpha: 0.1),
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: AppTheme.warning, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'وضع العرض التوضيحي — البيانات تجريبية',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(
                Icons.list_alt_outlined,
                color: AppTheme.primary,
              ),
              title: const Text('الطلبات'),
              subtitle: const Text('طلبات إضافة الشبكات وحالاتها'),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MyRequestsScreen()),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(
                Icons.account_balance_outlined,
                color: AppTheme.primary,
              ),
              title: const Text('الإيداعات'),
              subtitle: const Text('طلبات الإيداع وحالة التحقق المحلي'),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DepositHistoryScreen()),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(
                Icons.support_agent_outlined,
                color: AppTheme.primary,
              ),
              title: const Text('الدعم والشكاوى'),
              subtitle: const Text('التذاكر والشكاوى والنزاعات'),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MySupportScreen()),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(
                Icons.notifications_outlined,
                color: AppTheme.primary,
              ),
              title: const Text('مركز الإشعارات'),
              subtitle: const Text('سجل الإشعارات والتنبيهات'),
              trailing: const Icon(Icons.chevron_left),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const NotificationCenterScreen(),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.tune, color: AppTheme.primary),
              title: const Text('إعدادات الإشعارات'),
              subtitle: const Text('التحكم في فئات التفاعل'),
              trailing: const Icon(Icons.chevron_left),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const NotificationPreferencesScreen(),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          const _OwnerDashboardEntryCard(),
          const SizedBox(height: 12),
          const _AdminDashboardEntryCard(),
          const Card(
            child: ListTile(
              leading: Icon(Icons.info_outline, color: AppTheme.primary),
              title: Text('عن التطبيق'),
              subtitle: Text(
                '${AppConstants.appNameAr} — الإصدار ${AppConstants.appVersion}',
              ),
            ),
          ),
          const Card(
            child: ListTile(
              leading: Icon(
                Icons.privacy_tip_outlined,
                color: AppTheme.primary,
              ),
              title: Text('الخصوصية'),
              subtitle: Text(
                'لا يتم رفع BSSID أو هوية الجهاز أو إحداثيات الموقع',
              ),
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: user != null
                ? OutlinedButton.icon(
                    onPressed: config.isConfigured
                        ? () async {
                            await ref
                                .read(fcmTokenServiceProvider)
                                .stop(deactivateToken: true);
                            await Supabase.instance.client.auth.signOut();
                          }
                        : null,
                    icon: const Icon(Icons.logout),
                    label: const Text('تسجيل الخروج'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.error,
                      side: const BorderSide(color: AppTheme.error),
                    ),
                  )
                : ElevatedButton.icon(
                    onPressed: config.isConfigured
                        ? () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const LoginScreen(),
                              ),
                            );
                          }
                        : null,
                    icon: const Icon(Icons.login),
                    label: const Text('تسجيل الدخول'),
                  ),
          ),
        ],
      ),
    );
  }
}

class _OwnerDashboardEntryCard extends ConsumerWidget {
  const _OwnerDashboardEntryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final roles = ref.watch(currentUserRolesProvider).value ?? const <String>[];
    if (!config.isDemoMode &&
        !roles.contains('network_owner') &&
        !roles.contains('network_operator')) {
      return const SizedBox.shrink();
    }
    return Card(
      child: ListTile(
        leading: const Icon(Icons.dashboard_outlined, color: AppTheme.primary),
        title: const Text('عمليات الشبكة'),
        subtitle: const Text('الشبكات المملوكة والباقات والمخزون والملخصات'),
        trailing: const Icon(Icons.chevron_left),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const OwnerDashboardScreen())),
      ),
    );
  }
}

class _AdminDashboardEntryCard extends ConsumerWidget {
  const _AdminDashboardEntryCard();

  static const _adminRoles = {
    'platform_admin',
    'finance_officer',
    'support_agent',
    'system_auditor',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final rolesAsync = ref.watch(currentUserRolesProvider);

    final isVisible = config.isDemoMode ||
        rolesAsync.when(
          data: (roles) => roles.any(_adminRoles.contains),
          loading: () => false,
          error: (_, __) => false,
        );

    if (!isVisible) return const SizedBox.shrink();

    return Card(
      child: ListTile(
        leading: const Icon(
          Icons.admin_panel_settings_outlined,
          color: AppTheme.primary,
        ),
        title: const Text('لوحة الإدارة'),
        subtitle: const Text('إدارة الشبكات والطلبات والمستخدمين'),
        trailing: const Icon(Icons.chevron_left),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
          );
        },
      ),
    );
  }
}
