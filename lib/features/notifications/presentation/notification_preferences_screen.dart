import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/entities.dart';
import 'notification_permission_service.dart';
import 'notification_providers.dart';

class NotificationPreferencesScreen extends ConsumerStatefulWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  ConsumerState<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends ConsumerState<NotificationPreferencesScreen> {
  bool _saving = false;
  NotificationPermissionState _permission =
      NotificationPermissionState.unknown;

  @override
  void initState() {
    super.initState();
    _loadPermission();
  }

  Future<void> _loadPermission() async {
    final state =
        await ref.read(notificationPermissionServiceProvider).currentState();
    if (mounted) setState(() => _permission = state);
  }

  Future<void> _requestPermission() async {
    final service = ref.read(notificationPermissionServiceProvider);
    var state = await service.request();
    if (state == NotificationPermissionState.permanentlyDenied) {
      await service.openSystemSettings();
      state = await service.currentState();
    }
    if (mounted) setState(() => _permission = state);
  }

  Future<void> _save(NotificationPreferences next) async {
    setState(() => _saving = true);
    try {
      await ref.read(notificationRepositoryProvider).updatePreferences(next);
      ref.invalidate(notificationPreferencesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ تفضيلات الإشعارات')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر الحفظ: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefsAsync = ref.watch(notificationPreferencesProvider);
    final transportAsync = ref.watch(transportStatusProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('إعدادات الإشعارات'),
      ),
      body: prefsAsync.when(
        data: (prefs) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _PermissionCard(
              state: _permission,
              onRequest: _requestPermission,
            ),
            const SizedBox(height: 16),
            transportAsync.when(
              data: (t) => Card(
                color: AppTheme.warning.withValues(alpha: 0.08),
                child: ListTile(
                  leading: const Icon(Icons.info_outline, color: AppTheme.warning),
                  title: const Text('قناة الدفع الخارجية'),
                  subtitle: Text(
                    t.isUnbound
                        ? 'غير مربوطة بعد (OD-NOTIF-01). الإشعارات داخل التطبيق تعمل.'
                        : 'الحالة: ${t.bindingStatus}',
                  ),
                ),
              ),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 16),
            const Text(
              'إشعارات تشغيلية (إلزامية)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            const SwitchListTile(
              value: true,
              onChanged: null,
              title: Text('حالة الطلبات والمعاملات'),
              subtitle: Text(
                'لا يمكن تعطيل إشعارات الحالة التشغيلية والأمان',
              ),
            ),
            const Divider(height: 32),
            const Text(
              'إشعارات التفاعل (اختيارية)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              value: prefs.networkAddedEnabled,
              onChanged: _saving
                  ? null
                  : (v) => _save(prefs.copyWith(networkAddedEnabled: v)),
              title: const Text('شبكات جديدة'),
            ),
            SwitchListTile(
              value: prefs.packageAddedEnabled,
              onChanged: _saving
                  ? null
                  : (v) => _save(prefs.copyWith(packageAddedEnabled: v)),
              title: const Text('باقات جديدة'),
            ),
            SwitchListTile(
              value: prefs.stockRestoredEnabled,
              onChanged: _saving
                  ? null
                  : (v) => _save(prefs.copyWith(stockRestoredEnabled: v)),
              title: const Text('تجديد المخزون'),
            ),
            SwitchListTile(
              value: prefs.platformUpdatesEnabled,
              onChanged: _saving
                  ? null
                  : (v) => _save(prefs.copyWith(platformUpdatesEnabled: v)),
              title: const Text('تحديثات المنصة'),
            ),
            SwitchListTile(
              value: prefs.offersAnnouncementsEnabled,
              onChanged: _saving
                  ? null
                  : (v) =>
                      _save(prefs.copyWith(offersAnnouncementsEnabled: v)),
              title: const Text('العروض والإعلانات'),
            ),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('تعذر تحميل التفضيلات: $e')),
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  final NotificationPermissionState state;
  final VoidCallback onRequest;

  const _PermissionCard({
    required this.state,
    required this.onRequest,
  });

  @override
  Widget build(BuildContext context) {
    final granted = state == NotificationPermissionState.granted;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'إذن إشعارات أندرويد',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              granted
                  ? 'تم منح إذن الإشعارات.'
                  : 'فعّل إذن الإشعارات لتلقي التنبيهات على الجهاز. لا يتم تخزين مفاتيح مزوّد الدفع في التطبيق.',
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            if (!granted)
              ElevatedButton.icon(
                onPressed: onRequest,
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('طلب الإذن'),
              ),
          ],
        ),
      ),
    );
  }
}
