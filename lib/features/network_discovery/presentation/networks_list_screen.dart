import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../network_discovery/domain/entities.dart';
import '../../network_discovery/presentation/network_discovery_providers.dart';
import 'network_details_screen.dart';

class NetworksListScreen extends ConsumerWidget {
  const NetworksListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final networksAsync = ref.watch(filteredNetworksProvider);
    final searchQuery = ref.watch(networkSearchQueryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('الشبكات'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.read(networkCatalogProvider.notifier).refresh(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              onChanged: (v) =>
                  ref.read(networkSearchQueryProvider.notifier).state = v,
              decoration: InputDecoration(
                hintText: 'ابحث بالاسم أو المدينة أو SSID...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => ref
                            .read(networkSearchQueryProvider.notifier)
                            .state = '',
                      )
                    : null,
              ),
            ),
          ),
          Expanded(
            child: networksAsync.when(
              data: (networks) {
                if (networks.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.wifi_off,
                            size: 64, color: AppTheme.textMuted),
                        const SizedBox(height: 16),
                        const Text('لا توجد شبكات'),
                      ],
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () =>
                      ref.read(networkCatalogProvider.notifier).refresh(),
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: networks.length,
                    itemBuilder: (_, i) => _NetworkListCard(
                      network: networks[i],
                    ),
                  ),
                );
              },
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 48, color: AppTheme.error),
                    const SizedBox(height: 12),
                    const Text('حدث خطأ في تحميل الشبكات'),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => ref
                          .read(networkCatalogProvider.notifier)
                          .refresh(),
                      icon: const Icon(Icons.refresh),
                      label: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NetworkListCard extends StatelessWidget {
  final NetworkEntity network;
  const _NetworkListCard({required this.network});

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
          child: Row(
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
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            network.commercialName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const Icon(Icons.verified,
                            color: AppTheme.accent, size: 18),
                      ],
                    ),
                    if (network.locationText.isNotEmpty)
                      Text(
                        network.locationText,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    if (network.ssidAliases.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          network.ssidAliases
                              .map((a) => a.ssidDisplay)
                              .join(' · '),
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
