import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../providers/app_providers.dart';
import '../../../screens/auth/login_screen.dart';
import '../../../utils/constants.dart';
import '../../notifications/presentation/notification_center_screen.dart';
import '../../notifications/presentation/notification_providers.dart';
import '../../purchase/domain/entities.dart';
import '../../purchase/presentation/purchase_detail_screen.dart';
import '../../purchase/presentation/purchase_history_screen.dart';
import '../../purchase/presentation/purchase_providers.dart';
import '../../wallet/domain/entities.dart';
import '../../wallet/presentation/wallet_providers.dart';
import '../../wallet/presentation/wallet_screen.dart';
import '../domain/entities.dart';
import 'network_details_screen.dart';
import 'network_discovery_providers.dart';
import 'networks_list_screen.dart';
import 'scan_results_screen.dart';

class HomeScreen extends ConsumerWidget {
  final ValueChanged<int>? onSelectDestination;

  const HomeScreen({super.key, this.onSelectDestination});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final user = ref.watch(currentUserProvider);
    final hasCustomerSession = user != null || config.isDemoMode;
    final networksAsync = ref.watch(networkCatalogProvider);
    final walletAsync = hasCustomerSession
        ? ref.watch(walletSummaryProvider)
        : null;
    final purchasesAsync = hasCustomerSession
        ? ref.watch(purchaseHistoryProvider)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConstants.appNameAr),
        actions: [_NotificationAction(hasCustomerSession: hasCustomerSession)],
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: RefreshIndicator(
          onRefresh: () => _refresh(ref, hasCustomerSession),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _WelcomeCard(isSignedIn: hasCustomerSession),
              const SizedBox(height: 12),
              if (walletAsync != null)
                _WalletOverviewCard(
                  walletAsync: walletAsync,
                  onOpen: () => _openDestination(context, 2),
                )
              else
                _SignInCard(
                  onSignIn: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  ),
                ),
              const SizedBox(height: 12),
              _QuickActions(
                onNetworks: () => _openDestination(context, 1),
                onWallet: () => hasCustomerSession
                    ? _openDestination(context, 2)
                    : _openLogin(context),
                onPurchases: () => hasCustomerSession
                    ? _openDestination(context, 3)
                    : _openLogin(context),
              ),
              const SizedBox(height: 16),
              const _ScanSection(),
              const SizedBox(height: 20),
              _SectionHeader(
                title: 'شبكات مقترحة',
                actionLabel: 'عرض الكل',
                onAction: () => _openDestination(context, 1),
              ),
              const SizedBox(height: 8),
              _NetworkPreview(
                networksAsync: networksAsync,
                onRetry: () =>
                    ref.read(networkCatalogProvider.notifier).refresh(),
              ),
              if (purchasesAsync != null) ...[
                const SizedBox(height: 20),
                _SectionHeader(
                  title: 'آخر عملية شراء',
                  actionLabel: 'مشترياتي',
                  onAction: () => _openDestination(context, 3),
                ),
                const SizedBox(height: 8),
                _RecentPurchase(asyncValue: purchasesAsync),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _refresh(WidgetRef ref, bool hasCustomerSession) async {
    if (hasCustomerSession) {
      ref.invalidate(walletSummaryProvider);
      ref.invalidate(purchaseHistoryProvider);
      ref.invalidate(unreadNotificationCountProvider);
    }
    await ref.read(networkCatalogProvider.notifier).refresh();
  }

  void _openDestination(BuildContext context, int index) {
    final selectDestination = onSelectDestination;
    if (selectDestination != null) {
      selectDestination(index);
      return;
    }

    final Widget screen = switch (index) {
      1 => const NetworksListScreen(),
      2 => const WalletScreen(),
      3 => const PurchaseHistoryScreen(),
      _ => const NetworksListScreen(),
    };
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  void _openLogin(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }
}

class _WelcomeCard extends StatelessWidget {
  final bool isSignedIn;

  const _WelcomeCard({required this.isSignedIn});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primary,
            AppTheme.primary.withValues(alpha: 0.78),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isSignedIn ? 'مرحبًا بك في واصل نت' : 'الإنترنت أقرب إليك',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isSignedIn
                ? 'اكتشف الشبكات المعتمدة واشترِ كرتك من مكان واحد.'
                : 'اكتشف الشبكات والباقات المتاحة، وسجّل الدخول عند الشراء.',
            style: const TextStyle(color: Colors.white70, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _WalletOverviewCard extends StatelessWidget {
  final AsyncValue<WalletSummary> walletAsync;
  final VoidCallback onOpen;

  const _WalletOverviewCard({
    required this.walletAsync,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        key: const Key('home-open-wallet'),
        onTap: onOpen,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const CircleAvatar(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                child: Icon(Icons.account_balance_wallet_outlined),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'رصيد المحفظة',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 4),
                    walletAsync.when(
                      data: (wallet) => Text(
                        '${wallet.balance} ${wallet.currency}',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      loading: () => const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      error: (_, __) => const Text('تعذر تحميل الرصيد'),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_left),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignInCard extends StatelessWidget {
  final VoidCallback onSignIn;

  const _SignInCard({required this.onSignIn});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.lock_outline, color: AppTheme.primary),
        title: const Text('سجّل الدخول للشراء والمحفظة'),
        subtitle: const Text('يمكنك تصفح الشبكات والباقات دون تسجيل.'),
        trailing: TextButton(
          onPressed: onSignIn,
          child: const Text('دخول'),
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  final VoidCallback onNetworks;
  final VoidCallback onWallet;
  final VoidCallback onPurchases;

  const _QuickActions({
    required this.onNetworks,
    required this.onWallet,
    required this.onPurchases,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _QuickAction(
            key: const Key('home-open-networks'),
            icon: Icons.wifi,
            label: 'الشبكات',
            onTap: onNetworks,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _QuickAction(
            icon: Icons.add_card_outlined,
            label: 'شحن المحفظة',
            onTap: onWallet,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _QuickAction(
            icon: Icons.receipt_long_outlined,
            label: 'مشترياتي',
            onTap: onPurchases,
          ),
        ),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          child: Column(
            children: [
              Icon(icon, color: AppTheme.primary),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanSection extends ConsumerWidget {
  const _ScanSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.radar, color: AppTheme.primary, size: 34),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'اعثر على شبكة قريبة',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'المسح يدوي ولا يرفع BSSID أو هوية جهازك.',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton(
              onPressed: () async {
                await ref.read(scanNotifierProvider).performScan();
                if (context.mounted) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ScanResultsScreen(),
                    ),
                  );
                }
              },
              child: const Text('مسح'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String actionLabel;
  final VoidCallback onAction;

  const _SectionHeader({
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        TextButton(onPressed: onAction, child: Text(actionLabel)),
      ],
    );
  }
}

class _NetworkPreview extends StatelessWidget {
  final AsyncValue<List<NetworkEntity>> networksAsync;
  final VoidCallback onRetry;

  const _NetworkPreview({
    required this.networksAsync,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return networksAsync.when(
      data: (networks) {
        if (networks.isEmpty) {
          return const _CompactState(
            icon: Icons.wifi_off,
            message: 'لا توجد شبكات معتمدة حاليًا.',
          );
        }
        return Column(
          children: networks
              .take(3)
              .map((network) => _NetworkCard(network: network))
              .toList(),
        );
      },
      loading: () => const _PreviewLoading(),
      error: (_, __) => _CompactState(
        icon: Icons.cloud_off_outlined,
        message: 'تعذر تحميل الشبكات. تحقق من الاتصال وحاول مجددًا.',
        actionLabel: 'إعادة المحاولة',
        onAction: onRetry,
      ),
    );
  }
}

class _NetworkCard extends StatelessWidget {
  final NetworkEntity network;

  const _NetworkCard({required this.network});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => NetworkDetailsScreen(network: network),
          ),
        ),
        leading: CircleAvatar(
          backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
          child: Text(
            network.commercialName.isEmpty ? '?' : network.commercialName[0],
            style: const TextStyle(
              color: AppTheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Row(
          children: [
            Expanded(child: Text(network.commercialName)),
            const Icon(Icons.verified, color: AppTheme.accent, size: 18),
          ],
        ),
        subtitle: network.locationText.isEmpty
            ? const Text('شبكة معتمدة')
            : Text(network.locationText),
        trailing: const Icon(Icons.chevron_left),
      ),
    );
  }
}

class _RecentPurchase extends StatelessWidget {
  final AsyncValue<List<PurchaseOrder>> asyncValue;

  const _RecentPurchase({required this.asyncValue});

  @override
  Widget build(BuildContext context) {
    return asyncValue.when(
      data: (purchases) {
        if (purchases.isEmpty) {
          return const _CompactState(
            icon: Icons.shopping_bag_outlined,
            message: 'لا توجد مشتريات بعد. ابدأ باختيار شبكة وباقة.',
          );
        }
        final purchase = purchases.first;
        return Card(
          child: ListTile(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PurchaseDetailScreen(purchaseId: purchase.id),
              ),
            ),
            leading: const Icon(Icons.receipt_long, color: AppTheme.primary),
            title: Text(purchase.packageName ?? 'باقة إنترنت'),
            subtitle: Text(
              '${purchase.networkName ?? 'شبكة'} · '
              '${purchase.totalPrice} ${purchase.currency}',
            ),
            trailing: const Icon(Icons.chevron_left),
          ),
        );
      },
      loading: () => const _PreviewLoading(),
      error: (_, __) => const _CompactState(
        icon: Icons.receipt_long_outlined,
        message: 'تعذر تحميل آخر عملية شراء.',
      ),
    );
  }
}

class _CompactState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _CompactState({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.textMuted),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
            if (actionLabel != null)
              TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ),
      ),
    );
  }
}

class _PreviewLoading extends StatelessWidget {
  const _PreviewLoading();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _NotificationAction extends ConsumerWidget {
  final bool hasCustomerSession;

  const _NotificationAction({required this.hasCustomerSession});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = hasCustomerSession
        ? ref.watch(unreadNotificationCountProvider).valueOrNull ?? 0
        : 0;

    return IconButton(
      tooltip: 'الإشعارات',
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => hasCustomerSession
              ? const NotificationCenterScreen()
              : const LoginScreen(),
        ),
      ),
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        child: const Icon(Icons.notifications_outlined),
      ),
    );
  }
}
