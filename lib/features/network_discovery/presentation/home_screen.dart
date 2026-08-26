import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../utils/constants.dart';
import '../../network_discovery/domain/entities.dart';
import '../../network_discovery/presentation/network_discovery_providers.dart';
import '../../notifications/presentation/notification_center_screen.dart';
import '../../notifications/presentation/notification_providers.dart';
import 'network_details_screen.dart';
import 'scan_results_screen.dart';
import '../../network_requests/presentation/add_request_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final networksAsync = ref.watch(filteredNetworksProvider);
    final searchQuery = ref.watch(networkSearchQueryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConstants.appNameAr),
        actions: [
          const _NotificationAction(),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.read(networkCatalogProvider.notifier).refresh(),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                TextField(
                  onChanged: (v) =>
                      ref.read(networkSearchQueryProvider.notifier).state = v,
                  decoration: InputDecoration(
                    hintText: 'ابحث عن شبكة أو مدينة أو SSID...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _ClearSearchButton(query: searchQuery),
                  ),
                ),
                const SizedBox(height: 16),
                _ScanSection(),
                const SizedBox(height: 16),
                const Text(
                  'الشبكات المعتمدة',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
              ]),
            ),
          ),
          SliverFillRemaining(
            child: networksAsync.when(
              data: (networks) {
                if (networks.isEmpty) {
                  return const _EmptyCatalogState();
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: networks.length,
                  itemBuilder: (_, i) => _NetworkCard(network: networks[i]),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _ErrorState(
                message: 'حدث خطأ في تحميل الشبكات',
                onRetry: () =>
                    ref.read(networkCatalogProvider.notifier).refresh(),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AddRequestScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('طلب إضافة شبكة'),
      ),
    );
  }
}

class _ClearSearchButton extends ConsumerWidget {
  final String query;
  const _ClearSearchButton({required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (query.isEmpty) return const SizedBox.shrink();
    return IconButton(
      icon: const Icon(Icons.clear),
      onPressed: () => ref.read(networkSearchQueryProvider.notifier).state = '',
    );
  }
}

class _ScanSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.wifi_find, color: AppTheme.primary, size: 28),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'البحث عن شبكات قريبة',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'المسح يتم بضغط منك فقط. لا يتم رفع BSSID أو هوية الجهاز.',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await ref.read(scanNotifierProvider).performScan();
                  if (context.mounted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ScanResultsScreen(),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.radar),
                label: const Text('مسح الشبكات القريبة'),
              ),
            ),
          ],
        ),
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
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => NetworkDetailsScreen(network: network),
          ),
        ),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                    child: Text(
                      network.commercialName.isNotEmpty
                          ? network.commercialName[0]
                          : '?',
                      style: const TextStyle(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          network.commercialName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (network.locationText.isNotEmpty)
                          Text(
                            network.locationText,
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Icon(Icons.verified, color: AppTheme.accent, size: 20),
                ],
              ),
              if (network.ssidAliases.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: network.ssidAliases
                      .map(
                        (a) => Chip(
                          label: Text(
                            a.ssidDisplay,
                            style: const TextStyle(fontSize: 11),
                          ),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      )
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyCatalogState extends StatelessWidget {
  const _EmptyCatalogState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off, size: 64, color: AppTheme.textMuted),
          SizedBox(height: 16),
          Text('لا توجد شبكات معتمدة حالياً'),
          SizedBox(height: 8),
          Text(
            'يمكنك إرسال طلب إضافة شبكة جديدة',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: AppTheme.error),
          const SizedBox(height: 12),
          Text(message),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }
}

class _NotificationAction extends ConsumerWidget {
  const _NotificationAction();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadAsync = ref.watch(unreadNotificationCountProvider);
    final count = unreadAsync.valueOrNull ?? 0;

    return IconButton(
      tooltip: 'الإشعارات',
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const NotificationCenterScreen()),
        );
      },
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        child: const Icon(Icons.notifications_outlined),
      ),
    );
  }
}
