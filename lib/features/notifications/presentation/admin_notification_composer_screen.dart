import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/admin_notification_policy.dart';
import 'notification_providers.dart';

class AdminNotificationComposerScreen extends ConsumerStatefulWidget {
  const AdminNotificationComposerScreen({super.key});

  @override
  ConsumerState<AdminNotificationComposerScreen> createState() =>
      _AdminNotificationComposerScreenState();
}

class _AdminNotificationComposerScreenState
    extends ConsumerState<AdminNotificationComposerScreen> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  final _audienceValueCtrl = TextEditingController();
  String _audienceType = 'all_active_customers';
  String _channelClass = 'announcement';
  bool _sending = false;
  Map<String, dynamic>? _lastSummary;

  static const _audiences = <String, String>{
    'all_active_customers': 'كل العملاء النشطين',
    'governorate': 'محافظة',
    'city': 'مدينة',
    'network_related': 'أعضاء شبكة',
    'network_owner_operator': 'مالك/مشغّل شبكة',
    'specific_user': 'مستخدم محدد',
    'role_based': 'حسب الدور',
  };

  static const _channels = <String, String>{
    'announcement': 'إعلان',
    'platform_update': 'تحديث المنصة',
    'offer': 'عرض',
  };

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _audienceValueCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic> _audiencePayload() {
    switch (_audienceType) {
      case 'governorate':
        return {'governorate': _audienceValueCtrl.text.trim()};
      case 'city':
        return {'city': _audienceValueCtrl.text.trim()};
      case 'network_related':
      case 'network_owner_operator':
        return {'network_id': _audienceValueCtrl.text.trim()};
      case 'specific_user':
        return {'user_id': _audienceValueCtrl.text.trim()};
      case 'role_based':
        return {'role': _audienceValueCtrl.text.trim()};
      default:
        return {};
    }
  }

  Future<void> _send() async {
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    final validationMessage = AdminNotificationPolicy.validate(
      title: title,
      body: body,
      audienceType: _audienceType,
      audienceValue: _audienceValueCtrl.text,
    );
    if (validationMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(validationMessage)));
      return;
    }

    final confirmed = await _confirmSend();
    if (!confirmed || !mounted) return;

    setState(() {
      _sending = true;
      _lastSummary = null;
    });

    try {
      final result =
          await ref.read(notificationRepositoryProvider).adminCompose(
                titleAr: title,
                bodyAr: body,
                audienceType: _audienceType,
                audiencePayload: _audiencePayload(),
                channelClass: _channelClass,
                deepLink: 'notifications',
              );
      final summary = await ref
          .read(notificationRepositoryProvider)
          .adminDeliverySummary(result.eventId);
      if (mounted) {
        setState(() => _lastSummary = summary);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إنشاء حدث الإعلان من جهة الخادم')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر إنشاء الإعلان. تحقق من البيانات وحاول مجدداً.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<bool> _confirmSend() async {
    final audienceLabel = _audiences[_audienceType] ?? 'الجمهور المحدد';
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('تأكيد إنشاء الإعلان'),
            content: Text(
              'سيُنشأ الإعلان من الخادم للجمهور: $audienceLabel. هل تريد المتابعة؟',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('إنشاء الإعلان'),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final needsAudienceValue = _audienceType != 'all_active_customers';

    return Scaffold(
      appBar: AppBar(title: const Text('مؤلف الإعلانات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'معاينة عربية',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Card(
            color: AppTheme.primary.withValues(alpha: 0.06),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _titleCtrl.text.isEmpty ? 'عنوان الإعلان' : _titleCtrl.text,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _bodyCtrl.text.isEmpty ? 'نص الإعلان...' : _bodyCtrl.text,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(
              labelText: 'العنوان (عربي)',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
            maxLength: AdminNotificationPolicy.maximumTitleLength,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bodyCtrl,
            decoration: const InputDecoration(
              labelText: 'النص (عربي)',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
            maxLines: 4,
            maxLength: AdminNotificationPolicy.maximumBodyLength,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _channelClass,
            decoration: const InputDecoration(
              labelText: 'التصنيف',
              border: OutlineInputBorder(),
            ),
            items: _channels.entries
                .map(
                  (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _channelClass = v);
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _audienceType,
            decoration: const InputDecoration(
              labelText: 'الجمهور',
              border: OutlineInputBorder(),
            ),
            items: _audiences.entries
                .map(
                  (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _audienceType = v);
            },
          ),
          if (needsAudienceValue) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _audienceValueCtrl,
              decoration: InputDecoration(
                labelText: _audienceType == 'governorate'
                    ? 'اسم المحافظة'
                    : _audienceType == 'city'
                        ? 'اسم المدينة'
                        : _audienceType == 'role_based'
                            ? 'الدور'
                            : 'المعرّف',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_outlined),
            label: Text(
              _sending ? 'جاري الإنشاء...' : 'إنشاء وإرسال من الخادم',
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'لا يوجد إرسال من العميل مباشرة. الحدث يُنشأ على الخادم فقط.',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          if (_lastSummary != null) ...[
            const SizedBox(height: 24),
            const Text(
              'ملخص التسليم',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'الحدث: ${_lastSummary!['event_id']}\n'
                  'الإجمالي: ${_lastSummary!['total_deliveries']}\n'
                  'الحالات: ${_lastSummary!['counts']}',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
