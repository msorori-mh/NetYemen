import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config_provider.dart';
import '../../../core/providers/supabase_service_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../notifications/presentation/fcm_token_service.dart';
import '../data/account_deletion_repository.dart';

typedef LegalUrlLauncher = Future<bool> Function(Uri uri);

final legalUrlLauncherProvider = Provider<LegalUrlLauncher>((ref) {
  return (uri) => launchUrl(uri, mode: LaunchMode.externalApplication);
});

class PrivacyPolicyScreen extends ConsumerWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('سياسة الخصوصية')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'خصوصيتك في واصل نت',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Text(
            'نستخدم رقم الهاتف والاسم وموقع التسجيل الذي تختاره وبيانات '
            'الشبكات والمعاملات لتشغيل الحساب وتقديم الخدمة ومنع الاحتيال. '
            'لا نخزّن BSSID أو عنوان MAC أو هوية جهازك أو موقع المسح.',
          ),
          const SizedBox(height: 12),
          const Text(
            'تُحمى البيانات بصلاحيات وصول مقيدة وسجلات تدقيق. عند طلب حذف '
            'الحساب تبدأ مهلة تسوية مدتها 30 يومًا، ثم تُزال البيانات الشخصية. '
            'تُحتفظ السجلات المالية والتدقيقية التي يلزم حفظها قانونيًا بعد '
            'فصلها عن بياناتك التعريفية.',
          ),
          const SizedBox(height: 24),
          _PublicLegalLink(
            key: const Key('public-privacy-policy-link'),
            label: 'فتح السياسة الكاملة على الويب',
            uri: config.privacyPolicyUri,
          ),
          const SizedBox(height: 8),
          _PublicLegalLink(
            key: const Key('public-account-deletion-link'),
            label: 'فتح صفحة حذف الحساب على الويب',
            uri: config.accountDeletionUri,
          ),
        ],
      ),
    );
  }
}

class _PublicLegalLink extends ConsumerWidget {
  final String label;
  final Uri? uri;

  const _PublicLegalLink({super.key, required this.label, required this.uri});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OutlinedButton.icon(
      onPressed: uri == null
          ? null
          : () async {
              var opened = false;
              try {
                opened = await ref.read(legalUrlLauncherProvider)(uri!);
              } catch (_) {
                opened = false;
              }
              if (!opened && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تعذر فتح الرابط الآمن.')),
                );
              }
            },
      icon: const Icon(Icons.open_in_new),
      label: Text(label),
    );
  }
}

class AccountDeletionScreen extends ConsumerStatefulWidget {
  const AccountDeletionScreen({super.key});

  @override
  ConsumerState<AccountDeletionScreen> createState() =>
      _AccountDeletionScreenState();
}

class _AccountDeletionScreenState extends ConsumerState<AccountDeletionScreen> {
  static const confirmationPhrase = 'حذف حسابي';

  final _reasonController = TextEditingController();
  final _confirmationController = TextEditingController();
  bool _understood = false;
  bool _submitting = false;
  String? _errorMessage;

  bool get _canSubmit =>
      _understood &&
      _confirmationController.text.trim() == confirmationPhrase &&
      !_submitting;

  @override
  void dispose() {
    _reasonController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تأكيد طلب حذف الحساب'),
        content: const Text(
          'سيُغلق الحساب فورًا وتبدأ مهلة التسوية لمدة 30 يومًا. '
          'هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('تراجع'),
          ),
          FilledButton(
            key: const Key('confirm-account-deletion-button'),
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('تأكيد الحذف'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    late final AccountDeletionReceipt receipt;
    try {
      receipt = await ref
          .read(accountDeletionRepositoryProvider)
          .requestDeletion(
            reason: _reasonController.text.trim().isEmpty
                ? null
                : _reasonController.text.trim(),
          );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'تعذر تسجيل طلب الحذف بأمان. تحقق من الاتصال ثم أعد المحاولة.';
        _submitting = false;
      });
      return;
    }

    try {
      await ref.read(fcmTokenServiceProvider).stop(deactivateToken: true);
    } catch (_) {
      // The server already deactivated all push tokens atomically with the
      // deletion request. Local cleanup must not change the confirmed result.
    }

    var signedOut = true;
    try {
      await ref.read(supabaseServiceProvider).signOut();
    } catch (_) {
      signedOut = false;
    }

    if (!mounted) return;
    setState(() => _submitting = false);
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).popUntil((route) => route.isFirst);
    messenger.showSnackBar(
      SnackBar(content: Text(_successMessage(receipt, signedOut: signedOut))),
    );
  }

  String _successMessage(
    AccountDeletionReceipt receipt, {
    required bool signedOut,
  }) {
    final scheduled = receipt.scheduledFor.toLocal();
    final date = '${scheduled.day}/${scheduled.month}/${scheduled.year}';
    final prefix = receipt.idempotent
        ? 'طلب حذف الحساب مسجل مسبقًا'
        : 'تم استلام طلب حذف الحساب';
    if (!signedOut) {
      return '$prefix، وموعد إزالة البيانات الشخصية $date. '
          'تعذر تسجيل الخروج تلقائيًا؛ استخدم زر تسجيل الخروج من الحساب.';
    }
    return '$prefix وإغلاقه. موعد إزالة البيانات الشخصية $date.';
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(appConfigProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('حذف الحساب')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(Icons.person_remove_outlined,
              size: 56, color: AppTheme.error),
          const SizedBox(height: 16),
          const Text(
            'قبل حذف الحساب',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Text(
            'يُغلق الحساب فور إرسال الطلب، وتتوقف الإشعارات والعمليات. '
            'بعد 30 يومًا تُزال بياناتك الشخصية، مع الاحتفاظ بالسجلات المالية '
            'والتدقيقية اللازمة بعد فصلها عن بياناتك التعريفية.',
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('account-deletion-reason-field'),
            controller: _reasonController,
            maxLength: 500,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'سبب الحذف (اختياري)',
              border: OutlineInputBorder(),
            ),
          ),
          CheckboxListTile(
            key: const Key('account-deletion-understood-checkbox'),
            value: _understood,
            onChanged: _submitting
                ? null
                : (value) => setState(() => _understood = value ?? false),
            title: const Text('أفهم أن الحساب سيُغلق فورًا'),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('account-deletion-confirmation-field'),
            controller: _confirmationController,
            onChanged: (_) => setState(() {}),
            enabled: !_submitting,
            decoration: const InputDecoration(
              labelText: 'اكتب «حذف حسابي» للتأكيد',
              border: OutlineInputBorder(),
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              key: const Key('account-deletion-error'),
              style: const TextStyle(color: AppTheme.error),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            key: const Key('request-account-deletion-button'),
            onPressed: _canSubmit ? _submit : null,
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            icon: _submitting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_forever),
            label: const Text('طلب حذف الحساب'),
          ),
          const SizedBox(height: 12),
          _PublicLegalLink(
            label: 'سياسة حذف الحساب على الويب',
            uri: config.accountDeletionUri,
          ),
        ],
      ),
    );
  }
}
