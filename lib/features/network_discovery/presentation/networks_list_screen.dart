import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../network_discovery/domain/entities.dart';
import '../../network_discovery/presentation/network_discovery_providers.dart';
import 'network_details_screen.dart';

class NetworksListScreen extends ConsumerStatefulWidget {
  const NetworksListScreen({super.key});

  @override
  ConsumerState<NetworksListScreen> createState() =>
      _NetworksListScreenState();
}

class _NetworksListScreenState extends ConsumerState<NetworksListScreen> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: ref.read(networkSearchQueryProvider),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final networksAsync = ref.watch(filteredNetworksProvider);
    final catalogAsync = ref.watch(networkCatalogProvider);
    final searchQuery = ref.watch(networkSearchQueryProvider);
    final governorates = ref.watch(availableNetworkGovernoratesProvider);
    final selectedGovernorate = ref.watch(networkGovernorateFilterProvider);
    final hasActiveFilter =
        searchQuery.trim().isNotEmpty || selectedGovernorate != null;

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
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              key: const Key('network-search-field'),
              controller: _searchController,
              onChanged: (v) =>
                  ref.read(networkSearchQueryProvider.notifier).state = v,
              decoration: InputDecoration(
                hintText: 'ابحث بالاسم أو المدينة أو SSID...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: searchQuery.isNotEmpty
                    ? IconButton(
                        key: const Key('network-search-clear'),
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          ref.read(networkSearchQueryProvider.notifier).state =
                              '';
                        },
                      )
                    : null,
              ),
            ),
          ),
          if (governorates.length > 1)
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: FilterChip(
                      label: const Text('الكل'),
                      selected: selectedGovernorate == null,
                      onSelected: (_) => ref
                          .read(networkGovernorateFilterProvider.notifier)
                          .state = null,
                    ),
                  ),
                  ...governorates.map(
                    (governorate) => Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: FilterChip(
                        key: Key('network-governorate-$governorate'),
                        label: Text(governorate),
                        selected: selectedGovernorate == governorate,
                        onSelected: (_) => ref
                            .read(networkGovernorateFilterProvider.notifier)
                            .state = governorate,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: networksAsync.when(
              data: (networks) {
                if (networks.isEmpty) {
                  final catalogIsEmpty = catalogAsync.valueOrNull?.isEmpty ??
                      !hasActiveFilter;
                  return _NetworkEmptyState(
                    isFiltered: !catalogIsEmpty && hasActiveFilter,
                    onClear: _clearFilters,
                  );
                }
                return RefreshIndicator(
                  onRefresh: () =>
                      ref.read(networkCatalogProvider.notifier).refresh(),
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: networks.length,
                    itemBuilder: (_, i) =>
                        _NetworkListCard(network: networks[i]),
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 48,
                      color: AppTheme.error,
                    ),
                    const SizedBox(height: 12),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        'تعذر تحميل الشبكات. تحقق من اتصال الإنترنت ثم حاول مجددًا.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () =>
                          ref.read(networkCatalogProvider.notifier).refresh(),
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

  void _clearFilters() {
    _searchController.clear();
    ref.read(networkSearchQueryProvider.notifier).state = '';
    ref.read(networkGovernorateFilterProvider.notifier).state = null;
  }
}

class _NetworkEmptyState extends StatelessWidget {
  final bool isFiltered;
  final VoidCallback onClear;

  const _NetworkEmptyState({
    required this.isFiltered,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off, size: 64, color: AppTheme.textMuted),
            const SizedBox(height: 16),
            Text(
              isFiltered
                  ? 'لا توجد نتائج مطابقة لبحثك'
                  : 'لا توجد شبكات معتمدة حاليًا',
              textAlign: TextAlign.center,
            ),
            if (isFiltered) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                key: const Key('network-filters-clear'),
                onPressed: onClear,
                icon: const Icon(Icons.filter_alt_off_outlined),
                label: const Text('مسح البحث والفلاتر'),
              ),
            ],
          ],
        ),
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
                        const Icon(
                          Icons.verified,
                          color: AppTheme.accent,
                          size: 18,
                        ),
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
