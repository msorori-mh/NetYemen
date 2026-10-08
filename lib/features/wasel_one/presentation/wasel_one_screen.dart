import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config_provider.dart';
import '../../../core/security/secure_screen.dart';
import '../../../core/security/sensitive_clipboard.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money_format.dart';
import '../../auth/presentation/customer_session_providers.dart';
import '../../auth/presentation/login_screen.dart';
import '../../wallet/presentation/wallet_providers.dart';
import '../domain/entities.dart';
import 'wasel_one_providers.dart';

class WaselOneScreen extends ConsumerWidget {
  const WaselOneScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final isDemo = config.usesDemoData;
    final hasSession = ref.watch(currentUserProvider) != null || isDemo;
    final plans = ref.watch(waselOnePlansProvider);
    final purchaseState = ref.watch(waselOnePurchaseProvider);
    final isIssuingCredential = ref.watch(waselOneCredentialProvider).isLoading;
    final entitlements = hasSession
        ? ref.watch(waselOneEntitlementsProvider)
        : const AsyncValue<List<AccessEntitlement>>.data([]);

    return Scaffold(
      appBar: AppBar(title: const Text('واصل ون')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(waselOnePlansProvider);
          if (hasSession) ref.invalidate(waselOneEntitlementsProvider);
          await ref.read(waselOnePlansProvider.future);
        },
        child: ListView(
          key: const Key('wasel-one-screen'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            const _WaselOneHero(),
            if (isDemo) ...[const SizedBox(height: 12), const _PilotBanner()],
            const SizedBox(height: 20),
            if (!hasSession)
              _SignInRequired(
                onSignIn: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const LoginScreen())),
              )
            else ...[
              const _SectionTitle(
                title: 'دخولك الحالي',
                subtitle: 'بيانات دخول واحدة تعمل لدى الشبكات المشاركة.',
              ),
              const SizedBox(height: 8),
              _EntitlementsSection(
                entitlements: entitlements,
                isIssuing: isIssuingCredential,
                onIssue: (entitlement) =>
                    _issueCredential(context, ref, entitlement),
              ),
            ],
            const SizedBox(height: 22),
            const _SectionTitle(
              title: 'باقات واصل ون',
              subtitle:
                  'اختر مدة واستهلاكًا مناسبين، واستخدمهما عبر أكثر من شبكة.',
            ),
            const SizedBox(height: 8),
            _PlansSection(
              plans: plans,
              isPurchasing: purchaseState.isLoading,
              onPurchase: (plan) =>
                  _purchasePlan(context, ref, plan, hasSession),
            ),
            const SizedBox(height: 20),
            const _HowItWorks(),
          ],
        ),
      ),
    );
  }

  Future<void> _issueCredential(
    BuildContext context,
    WidgetRef ref,
    AccessEntitlement entitlement,
  ) async {
    // Captured before any await: `ref` must not be used after this widget is
    // unmounted, and the notifier outlives the screen.
    final notifier = ref.read(waselOneCredentialProvider.notifier);
    // Issuing a credential invalidates the previous one, so a double tap must
    // never issue twice while one is being created or is still on screen.
    if (!notifier.tryBegin()) return;
    try {
      final credential = await notifier.issue(entitlement.id);
      if (!context.mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        // The credential is a secret: block screenshots while it is shown.
        builder: (_) => SecureScreenScope(
          child: _CredentialSheet(credential: credential),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_friendlyError(error))));
    } finally {
      notifier.finish();
    }
  }

  Future<void> _purchasePlan(
    BuildContext context,
    WidgetRef ref,
    FederatedAccessPlan plan,
    bool hasSession,
  ) async {
    if (!hasSession) {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const LoginScreen()));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تأكيد شراء باقة واصل ون'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(plan.name,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('سيتم خصم ${_formatMoney(plan.retailPrice)} من محفظتك.'),
            const SizedBox(height: 8),
            const Text(
              'تعمل الصلاحية لدى جميع الشبكات الشريكة المشمولة في الباقة.',
              style: TextStyle(color: AppTheme.textSecondary, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            key: const Key('wasel-one-confirm-purchase'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('شراء وتفعيل'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    // Captured before the await: `ref` must not be used after unmount.
    final notifier = ref.read(waselOnePurchaseProvider.notifier);
    try {
      final result = await notifier.purchase(plan.id);
      if (!context.mounted) return;
      ref.invalidate(walletSummaryProvider);
      ref.invalidate(waselOneEntitlementsProvider);
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(
            Icons.check_circle_outline,
            color: Color(0xFF08705B),
            size: 42,
          ),
          title: const Text('تم تفعيل الباقة'),
          content: Text(
            'تم خصم ${_formatMoney(result.amountPaid)} وأصبحت صلاحية الدخول جاهزة ضمن «دخولك الحالي».',
            textAlign: TextAlign.center,
          ),
          actions: [
            FilledButton(
              key: const Key('wasel-one-purchase-done'),
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('حسنًا'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyPurchaseError(error))));
    } finally {
      notifier.clear();
    }
  }
}

class _WaselOneHero extends StatelessWidget {
  const _WaselOneHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF0E7490), Color(0xFF0F4C81)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F4C81).withValues(alpha: 0.22),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _OneBadge(),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'إنترنت بلا حدود الشبكة',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 14),
          Text(
            'اشترِ وصولًا واحدًا، ثم استخدمه تلقائيًا لدى أي شبكة شريكة متاحة في منطقتك.',
            style: TextStyle(color: Colors.white, height: 1.55, fontSize: 15),
          ),
          SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _HeroChip(icon: Icons.pin_drop_outlined, label: 'شبكات متعددة'),
              _HeroChip(icon: Icons.key_outlined, label: 'دخول واحد'),
              _HeroChip(icon: Icons.swap_horiz, label: 'تنقل سلس'),
            ],
          ),
        ],
      ),
    );
  }
}

class _OneBadge extends StatelessWidget {
  const _OneBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 54,
      height: 54,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Text(
        'ONE',
        style: TextStyle(
          color: Color(0xFF0F4C81),
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _HeroChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 17),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }
}

class _PilotBanner extends StatelessWidget {
  const _PilotBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('wasel-one-demo-banner'),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFD58A)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.science_outlined, color: Color(0xFF9A6700)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'وضع التجربة: البيانات الظاهرة آمنة وتجريبية ولا تخص مستخدمين أو شبكات حقيقية.',
              style: TextStyle(color: Color(0xFF6B4A00), height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionTitle({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: const TextStyle(color: AppTheme.textSecondary, height: 1.35),
        ),
      ],
    );
  }
}

class _SignInRequired extends StatelessWidget {
  final VoidCallback onSignIn;

  const _SignInRequired({required this.onSignIn});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const CircleAvatar(child: Icon(Icons.lock_outline)),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'سجّل الدخول لاستخدام واصل ون',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text('التصفح متاح، وإصدار بيانات الدخول يتطلب حسابك.'),
                ],
              ),
            ),
            TextButton(onPressed: onSignIn, child: const Text('دخول')),
          ],
        ),
      ),
    );
  }
}

class _EntitlementsSection extends StatelessWidget {
  final AsyncValue<List<AccessEntitlement>> entitlements;
  final bool isIssuing;
  final ValueChanged<AccessEntitlement> onIssue;

  const _EntitlementsSection({
    required this.entitlements,
    required this.isIssuing,
    required this.onIssue,
  });

  @override
  Widget build(BuildContext context) {
    return entitlements.when(
      loading: () => const _LoadingCard(),
      error: (_, __) =>
          const _InlineError(message: 'تعذر تحميل صلاحيات الدخول.'),
      data: (items) {
        final usable = items.where((item) => item.isUsable).toList();
        if (usable.isEmpty) {
          return const _EmptyEntitlement();
        }
        return Column(
          children: usable
              .map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _EntitlementCard(
                    entitlement: item,
                    isIssuing: isIssuing,
                    onIssue: () => onIssue(item),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _EntitlementCard extends StatelessWidget {
  final AccessEntitlement entitlement;
  final bool isIssuing;
  final VoidCallback onIssue;

  const _EntitlementCard({
    required this.entitlement,
    required this.isIssuing,
    required this.onIssue,
  });

  @override
  Widget build(BuildContext context) {
    final remaining = entitlement.remainingBytes;
    return Card(
      color: const Color(0xFFEFFAFB),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.verified_user_outlined,
                  color: Color(0xFF0E7490),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entitlement.planName,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const _StatusPill(label: 'فعّالة'),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _Metric(
                  icon: Icons.data_usage,
                  text: remaining == null
                      ? 'استخدام مرن'
                      : 'متبقي ${_formatBytes(remaining)}',
                ),
                _Metric(
                  icon: Icons.speed,
                  text: entitlement.speedLimitKbps == null
                      ? 'سرعة الشبكة'
                      : '${entitlement.speedLimitKbps} Kbps',
                ),
                _Metric(
                  icon: Icons.schedule,
                  text: 'حتى ${_formatDate(entitlement.expiresAt)}',
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('wasel-one-issue-credential'),
                onPressed: isIssuing ? null : onIssue,
                icon: const Icon(Icons.key_outlined),
                label: const Text('إنشاء بيانات دخول آمنة'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;

  const _StatusPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFCCF0E8),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF08705B),
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Metric({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: AppTheme.textSecondary),
        const SizedBox(width: 5),
        Text(text, style: const TextStyle(color: AppTheme.textSecondary)),
      ],
    );
  }
}

class _PlansSection extends StatelessWidget {
  final AsyncValue<List<FederatedAccessPlan>> plans;
  final bool isPurchasing;
  final ValueChanged<FederatedAccessPlan> onPurchase;

  const _PlansSection({
    required this.plans,
    required this.isPurchasing,
    required this.onPurchase,
  });

  @override
  Widget build(BuildContext context) {
    return plans.when(
      loading: () => const _LoadingCard(),
      error: (_, __) =>
          const _InlineError(message: 'تعذر تحميل باقات واصل ون.'),
      data: (items) {
        if (items.isEmpty) {
          return const _InlineError(
            message: 'لا توجد باقات منشورة في منطقتك حاليًا.',
          );
        }
        return Column(
          children: items
              .map(
                (plan) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _PlanCard(
                    plan: plan,
                    isPurchasing: isPurchasing,
                    onPurchase: () => onPurchase(plan),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _PlanCard extends StatelessWidget {
  final FederatedAccessPlan plan;
  final bool isPurchasing;
  final VoidCallback onPurchase;

  const _PlanCard({
    required this.plan,
    required this.isPurchasing,
    required this.onPurchase,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    plan.name,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  _formatMoney(plan.retailPrice),
                  style: const TextStyle(
                    color: AppTheme.primary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            if (plan.description?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 7),
              Text(
                plan.description!,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 14,
              runSpacing: 8,
              children: [
                _Metric(
                  icon: Icons.timer_outlined,
                  text: _formatDuration(plan.validity),
                ),
                _Metric(
                  icon: Icons.cloud_outlined,
                  text: plan.quotaBytes == null
                      ? 'استخدام مرن'
                      : _formatBytes(plan.quotaBytes!),
                ),
                _Metric(
                  icon: Icons.hub_outlined,
                  text: '${plan.partnerCount} شبكات شريكة',
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: Key('wasel-one-buy-${plan.id}'),
                onPressed: isPurchasing ? null : onPurchase,
                icon: isPurchasing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.shopping_bag_outlined),
                label: Text(isPurchasing ? 'جارٍ التفعيل…' : 'شراء وتفعيل'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyEntitlement extends StatelessWidget {
  const _EmptyEntitlement();

  @override
  Widget build(BuildContext context) {
    return const _InlineError(
      message: 'لا توجد باقة فعّالة. سيُفتح التفعيل عند بدء التجربة الميدانية.',
      icon: Icons.wifi_off_outlined,
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(22),
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  final String message;
  final IconData icon;

  const _InlineError({required this.message, this.icon = Icons.info_outline});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.textSecondary),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'كيف تستخدم واصل ون؟',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 14),
            _Step(number: '1', text: 'فعّل باقة واصل ون المناسبة.'),
            _Step(number: '2', text: 'اتصل بأي شبكة تحمل علامة واصل ون.'),
            _Step(
              number: '3',
              text: 'استخدم بيانات الدخول المؤقتة داخل صفحة الشبكة.',
            ),
            _Step(number: '4', text: 'انتقل إلى شبكة شريكة أخرى بنفس الباقة.'),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final String number;
  final String text;

  const _Step({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
            foregroundColor: AppTheme.primary,
            child: Text(number, style: const TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _CredentialSheet extends StatelessWidget {
  final RadiusAccessCredential credential;

  const _CredentialSheet({required this.credential});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        18,
        20,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(
            child: SizedBox(width: 42, child: Divider(thickness: 4)),
          ),
          const SizedBox(height: 10),
          const Row(
            children: [
              Icon(Icons.shield_outlined, color: Color(0xFF08705B)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'بيانات الدخول المؤقتة',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'لا ترسل هذه البيانات لشخص آخر. إنشاء بيانات جديدة يلغي البيانات السابقة.',
            style: TextStyle(color: AppTheme.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 16),
          _SecretField(label: 'اسم المستخدم', value: credential.username),
          const SizedBox(height: 10),
          _SecretField(label: 'كلمة المرور', value: credential.password),
          const SizedBox(height: 12),
          Text(
            'صالحة حتى ${_formatDateTime(credential.expiresAt)}',
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('تم'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SecretField extends ConsumerWidget {
  final String label;
  final String value;

  const _SecretField({required this.label, required this.value});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7F8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 3),
                SelectableText(
                  value,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'نسخ',
            onPressed: () async {
              // Wiped from the clipboard after a minute by the app-level
              // service, even if this sheet is closed first.
              await ref.read(sensitiveClipboardProvider).copy(value);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('تم نسخ $label — سيُمسح من الحافظة بعد دقيقة'),
                ),
              );
            },
            icon: const Icon(Icons.copy_outlined),
          ),
        ],
      ),
    );
  }
}

String _formatBytes(int bytes) {
  const gib = 1073741824;
  const mib = 1048576;
  if (bytes >= gib) {
    final value = bytes / gib;
    return '${value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 1)} GB';
  }
  return '${(bytes / mib).round()} MB';
}

String _formatDuration(Duration duration) {
  if (duration.inDays >= 1) {
    return duration.inDays == 1 ? '24 ساعة' : '${duration.inDays} أيام';
  }
  return '${duration.inHours} ساعة';
}

String _formatDate(DateTime value) {
  final local = value.toLocal();
  return '${local.day}/${local.month} ${_two(local.hour)}:${_two(local.minute)}';
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  return '${local.day}/${local.month}/${local.year} ${_two(local.hour)}:${_two(local.minute)}';
}

String _two(int value) => value.toString().padLeft(2, '0');

String _formatMoney(int amount) => formatYer(amount, currency: 'ر.ي');

String _friendlyError(Object error) {
  final value = error.toString();
  if (value.contains('ENTITLEMENT_NOT_ACTIVE')) {
    return 'هذه الباقة غير فعّالة أو انتهت صلاحيتها.';
  }
  if (value.contains('UNAUTHENTICATED')) {
    return 'يرجى تسجيل الدخول أولًا.';
  }
  return 'تعذر إنشاء بيانات الدخول. حاول مرة أخرى.';
}

String _friendlyPurchaseError(Object error) {
  final value = error.toString();
  if (value.contains('INSUFFICIENT_BALANCE')) {
    return 'رصيد المحفظة غير كافٍ لشراء هذه الباقة.';
  }
  if (value.contains('PLAN_UNAVAILABLE') ||
      value.contains('PLAN_HAS_NO_ACTIVE_NETWORKS')) {
    return 'هذه الباقة غير متاحة حاليًا. اختر باقة أخرى.';
  }
  if (value.contains('WALLET_UNAVAILABLE')) {
    return 'المحفظة غير متاحة حاليًا. تواصل مع الدعم.';
  }
  if (value.contains('UNAUTHENTICATED')) {
    return 'يرجى تسجيل الدخول أولًا.';
  }
  if (value.contains('WASEL_ONE_PURCHASE_ALREADY_IN_PROGRESS')) {
    return 'توجد عملية شراء قيد التنفيذ بالفعل.';
  }
  return 'تعذر تفعيل الباقة. لم يتم تأكيد الخصم، حاول مرة أخرى.';
}
