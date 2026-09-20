import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/app_config_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../utils/constants.dart';
import '../../auth/presentation/customer_auth_providers.dart';
import '../../auth/presentation/customer_session_providers.dart';
import '../../auth/presentation/login_screen.dart';
import '../../notifications/presentation/notification_center_screen.dart';
import '../../notifications/presentation/notification_preferences_screen.dart';
import '../../notifications/presentation/fcm_token_service.dart';
import '../../network_requests/presentation/my_requests_screen.dart';
import '../../support/presentation/support_screens.dart';
import '../../wallet/presentation/deposit_history_screen.dart';
import 'customer_profile_providers.dart';
import 'legal_and_deletion_screens.dart';
import 'profile_edit_screen.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _signingOut = false;

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(appConfigProvider);
    final user = ref.watch(currentUserProvider);
    final profileAsync = ref.watch(userProfileProvider);
    final profile = profileAsync.asData?.value;

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
                  user != null
                      ? (profile?.fullName?.trim().isNotEmpty == true
                          ? profile!.fullName!
                          : 'مستخدم واصل نت')
                      : 'غير مسجل',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (user != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    user.phone ?? user.email ?? '---',
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
          if (profile?.isActive == false)
            Card(
              key: const Key('profile-inactive-warning'),
              color: AppTheme.error.withValues(alpha: 0.08),
              child: const ListTile(
                leading: Icon(Icons.block_outlined, color: AppTheme.error),
                title: Text('الحساب غير نشط'),
                subtitle: Text(
                  'لا يمكن تعديل بيانات الحساب حاليًا. تواصل مع الدعم للمساعدة.',
                ),
              ),
            ),
          const SizedBox(height: 16),
          if (user != null)
            profileAsync.when(
              data: (profile) => Card(
                child: Column(
                  children: [
                    ListTile(
                      key: const Key('profile-edit-entry'),
                      leading: const Icon(
                        Icons.manage_accounts_outlined,
                        color: AppTheme.primary,
                      ),
                      title: const Text('تعديل الملف الشخصي'),
                      subtitle: Text(
                        profile == null
                            ? 'تعذر العثور على بيانات الملف الشخصي'
                            : '${profile.governorate ?? 'لم تحدد المحافظة'} — '
                                '${profile.city ?? 'لم تحدد المدينة'}',
                      ),
                      trailing: profile == null || !profile.isActive
                          ? null
                          : const Icon(Icons.chevron_left),
                      onTap: profile == null || !profile.isActive
                          ? null
                          : () async {
                              final updated =
                                  await Navigator.of(context).push<bool>(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      ProfileEditScreen(profile: profile),
                                ),
                              );
                              if (updated == true) {
                                ref.invalidate(userProfileProvider);
                              }
                            },
                    ),
                  ],
                ),
              ),
              loading: () => const Card(
                child: ListTile(
                  key: Key('profile-loading'),
                  leading: SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  title: Text('جارٍ تحميل الملف الشخصي...'),
                ),
              ),
              error: (_, __) => Card(
                child: ListTile(
                  key: const Key('profile-load-error'),
                  leading: const Icon(
                    Icons.error_outline,
                    color: AppTheme.error,
                  ),
                  title: const Text('تعذر تحميل الملف الشخصي'),
                  subtitle: const Text('تحقق من الاتصال ثم أعد المحاولة.'),
                  trailing: IconButton(
                    key: const Key('profile-retry-button'),
                    tooltip: 'إعادة المحاولة',
                    onPressed: () => ref.invalidate(userProfileProvider),
                    icon: const Icon(Icons.refresh),
                  ),
                ),
              ),
            ),
          if (user != null) const SizedBox(height: 12),
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
          const Card(
            child: ListTile(
              leading: Icon(Icons.info_outline, color: AppTheme.primary),
              title: Text('عن التطبيق'),
              subtitle: Text(
                '${AppConstants.appNameAr} — الإصدار ${AppConstants.appVersion}',
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(
                Icons.privacy_tip_outlined,
                color: AppTheme.primary,
              ),
              title: const Text('الخصوصية'),
              subtitle: const Text(
                'لا يتم رفع BSSID أو هوية الجهاز أو إحداثيات الموقع',
              ),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const PrivacyPolicyScreen(),
                ),
              ),
            ),
          ),
          if (user != null)
            Card(
              child: ListTile(
                key: const Key('account-deletion-entry'),
                leading: const Icon(
                  Icons.person_remove_outlined,
                  color: AppTheme.error,
                ),
                title: const Text('حذف الحساب'),
                subtitle:
                    const Text('إغلاق الحساب وطلب إزالة البيانات الشخصية'),
                trailing: const Icon(Icons.chevron_left),
                onTap: config.isConfigured
                    ? () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const AccountDeletionScreen(),
                          ),
                        )
                    : null,
              ),
            ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: user != null
                ? OutlinedButton.icon(
                    key: const Key('profile-sign-out'),
                    onPressed: config.isConfigured
                        ? (_signingOut ? null : _signOut)
                        : null,
                    icon: _signingOut
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.logout),
                    label: Text(
                      _signingOut ? 'جارٍ تسجيل الخروج...' : 'تسجيل الخروج',
                    ),
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

  Future<void> _signOut() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);

    try {
      try {
        await ref.read(fcmTokenServiceProvider).stop(deactivateToken: true);
      } catch (_) {
        // Token cleanup is best-effort and must never block account sign-out.
      }
      await ref.read(customerAuthRepositoryProvider).signOut();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تعذر تسجيل الخروج بأمان. تحقق من الاتصال ثم أعد المحاولة.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }
}
