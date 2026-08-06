import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../network_discovery/presentation/network_discovery_providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = Supabase.instance.client.auth.currentUser;
    final config = ref.watch(appConfigProvider);

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
                    style:
                        const TextStyle(color: AppTheme.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 32),
          if (config.isDemoMode)
            Card(
              color: AppTheme.warning.withValues(alpha: 0.1),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        color: AppTheme.warning, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
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
              leading: const Icon(Icons.info_outline, color: AppTheme.primary),
              title: const Text('عن التطبيق'),
              subtitle: const Text('نت اليمن — الإصدار 1.0.0'),
            ),
          ),
          Card(
            child: ListTile(
              leading:
                  const Icon(Icons.privacy_tip_outlined, color: AppTheme.primary),
              title: const Text('الخصوصية'),
              subtitle: const Text(
                'لا يتم رفع BSSID أو هوية الجهاز أو إحداثيات الموقع',
              ),
            ),
          ),
          if (user != null) ...[
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await Supabase.instance.client.auth.signOut();
                },
                icon: const Icon(Icons.logout),
                label: const Text('تسجيل الخروج'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.error,
                  side: const BorderSide(color: AppTheme.error),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
