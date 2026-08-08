import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/app_providers.dart';
import '../../../screens/auth/login_screen.dart';
import '../../admin/presentation/admin_dashboard_screen.dart';
import '../../packages/presentation/owner_dashboard_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('الحساب'),
      ),
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
              leading: const Icon(Icons.dashboard_outlined, color: AppTheme.primary),
              title: const Text('لوحة مالك الشبكة'),
              subtitle: const Text('إدارة الباقات والمخزون'),
              trailing: const Icon(Icons.chevron_left),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const OwnerDashboardScreen(),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          const _AdminDashboardEntryCard(),
          const Card(
            child: ListTile(
              leading: Icon(Icons.info_outline, color: AppTheme.primary),
              title: Text('عن التطبيق'),
              subtitle: Text('نت اليمن — الإصدار 1.0.0'),
            ),
          ),
          const Card(
            child: ListTile(
              leading:
                  Icon(Icons.privacy_tip_outlined, color: AppTheme.primary),
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

class _AdminDashboardEntryCard extends ConsumerWidget {
  const _AdminDashboardEntryCard();

  static const _adminRoles = {
    'platform_admin',
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
        leading: const Icon(Icons.admin_panel_settings_outlined,
            color: AppTheme.primary),
        title: const Text('لوحة الإدارة'),
        subtitle: const Text('إدارة الشبكات والطلبات والمستخدمين'),
        trailing: const Icon(Icons.chevron_left),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const AdminDashboardScreen(),
            ),
          );
        },
      ),
    );
  }
}
