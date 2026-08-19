// lib/screens/profile/profile_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/app_providers.dart';
import '../../utils/app_theme.dart';
import '../auth/login_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final service = ref.read(supabaseServiceProvider);
    await service.signOut();

    if (context.mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userProfileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('حسابي')),
      body: userAsync.when(
        data: (user) {
          if (user == null) {
            return const Center(child: Text('لم يتم العثور على المستخدم'));
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Profile Header
              Center(
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                      child: Text(
                        user.fullName?.isNotEmpty == true
                            ? user.fullName![0]
                            : user.phone[0],
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      user.fullName ?? 'مستخدم',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      user.phone,
                      style: const TextStyle(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Settings
              _buildSectionTitle('الإعدادات'),
              _buildListTile(
                icon: Icons.person_outline,
                title: 'تعديل الملف الشخصي',
                onTap: () {},
              ),
              _buildListTile(
                icon: Icons.location_on_outlined,
                title: 'الموقع',
                subtitle:
                    '${user.governorate ?? '---'} - ${user.city ?? '---'}',
                onTap: () {},
              ),

              const SizedBox(height: 16),
              _buildSectionTitle('الدعم'),
              _buildListTile(
                icon: Icons.help_outline,
                title: 'المساعدة',
                onTap: () {},
              ),
              _buildListTile(
                icon: Icons.info_outline,
                title: 'عن التطبيق',
                subtitle: 'الإصدار 1.0.0',
                onTap: () {},
              ),

              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _logout(context, ref),
                  icon: const Icon(Icons.logout),
                  label: const Text('تسجيل الخروج'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.error,
                    side: const BorderSide(color: AppTheme.error),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('حدث خطأ')),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: AppTheme.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildListTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: AppTheme.primary),
        title: Text(title),
        subtitle: subtitle != null ? Text(subtitle) : null,
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap,
      ),
    );
  }
}
