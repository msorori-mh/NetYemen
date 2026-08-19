import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/entities.dart';
import 'admin_common_widgets.dart';
import 'admin_network_detail_screen.dart';
import 'admin_providers.dart';

class AdminNetworksScreen extends ConsumerWidget {
  const AdminNetworksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final networksAsync = ref.watch(adminNetworksProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('الشبكات'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(adminNetworksProvider.notifier).refresh(),
          ),
        ],
      ),
      body: networksAsync.when(
        data: (networks) => _NetworksBody(
          networks: networks,
          onRefresh: () => ref.read(adminNetworksProvider.notifier).refresh(),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AdminErrorState(
          message: 'تعذر تحميل الشبكات. أعد المحاولة.',
          onRetry: () => ref.read(adminNetworksProvider.notifier).refresh(),
        ),
      ),
    );
  }
}

class _NetworksBody extends ConsumerStatefulWidget {
  final List<AdminNetwork> networks;
  final Future<void> Function() onRefresh;

  const _NetworksBody({required this.networks, required this.onRefresh});

  @override
  ConsumerState<_NetworksBody> createState() => _NetworksBodyState();
}

class _NetworksBodyState extends ConsumerState<_NetworksBody> {
  String? _statusFilter;
  String? _verificationFilter;
  String _searchQuery = '';

  List<AdminNetwork> get _filteredNetworks {
    return widget.networks.where((n) {
      if (_statusFilter != null && n.status != _statusFilter) return false;
      if (_verificationFilter != null &&
          n.verificationStatus != _verificationFilter) {
        return false;
      }
      if (_searchQuery.isEmpty) return true;

      final searchableText = [
        n.commercialName,
        n.governorate,
        n.city,
        n.district,
        ...n.ownerNames,
      ].whereType<String>().join(' ').toLowerCase();

      return searchableText.contains(_searchQuery);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AdminSearchField(
          hintText: 'ابحث باسم الشبكة أو المالك أو الموقع',
          onChanged: (value) => setState(() => _searchQuery = value),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              _FilterChip(
                label: 'الكل',
                selected: _statusFilter == null && _verificationFilter == null,
                onSelected: (_) => _applyFilters(null, null),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: 'في انتظار الموافقة',
                selected: _statusFilter == 'pending_approval',
                onSelected: (_) => _applyFilters('pending_approval', null),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: 'نشطة',
                selected: _statusFilter == 'active',
                onSelected: (_) => _applyFilters('active', null),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: 'معلّقة',
                selected: _statusFilter == 'suspended',
                onSelected: (_) => _applyFilters('suspended', null),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: 'غير موثّقة',
                selected: _verificationFilter == 'unverified',
                onSelected: (_) => _applyFilters(null, 'unverified'),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: widget.onRefresh,
            child: _filteredNetworks.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 120),
                      AdminEmptyState(
                        title: 'لا توجد شبكات',
                        subtitle: 'لا توجد شبكات تطابق الفلتر المحدد',
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _filteredNetworks.length,
                    itemBuilder: (_, i) =>
                        _NetworkCard(network: _filteredNetworks[i]),
                  ),
          ),
        ),
      ],
    );
  }

  void _applyFilters(String? status, String? verification) {
    setState(() {
      _statusFilter = status;
      _verificationFilter = verification;
    });
    ref
        .read(adminNetworksProvider.notifier)
        .setFilters(status: status, verificationStatus: verification);
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
    );
  }
}

class _NetworkCard extends StatelessWidget {
  final AdminNetwork network;

  const _NetworkCard({required this.network});

  @override
  Widget build(BuildContext context) {
    return AdminListCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AdminNetworkDetailScreen(networkId: network.id),
        ),
      ),
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
              AdminStatusChip(
                label: network.statusLabel,
                color: statusColor(network.status),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              AdminStatusChip(
                label: network.verificationStatusLabel,
                color: statusColor(network.verificationStatus),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (network.locationText.isNotEmpty)
            Text(
              network.locationText,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
              ),
            ),
          if (network.ownerNames.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'المالك: ${network.ownerNames.join(', ')}',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
