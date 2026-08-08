import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import 'owner_packages_screen.dart';
import 'package_providers.dart';

class OwnerDashboardScreen extends ConsumerWidget {
  const OwnerDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ownedNetworksAsync = ref.watch(ownedNetworksProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة مالك الشبكة'),
      ),
      body: ownedNetworksAsync.when(
        data: (networks) => _buildContent(context, networks),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorState(message: error.toString()),
      ),
    );
  }

  Widget _buildContent(BuildContext context, List<dynamic> networks) {
    if (networks.isEmpty) {
      return const _EmptyState();
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: networks.length,
      itemBuilder: (context, index) {
        final network = networks[index];
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
              child: Text(
                network.commercialName.isNotEmpty
                    ? network.commercialName[0]
                    : '?',
                style: const TextStyle(color: AppTheme.primary),
              ),
            ),
            title: Text(network.commercialName),
            subtitle: Text(
              network.locationText.isEmpty ? 'لا يوجد موقع' : network.locationText,
            ),
            trailing: const Icon(Icons.chevron_left),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => OwnerPackagesScreen(
                    networkId: network.id,
                    networkName: network.commercialName,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.business_outlined, size: 64, color: AppTheme.textSecondary),
          SizedBox(height: 16),
          Text(
            'لا تمتلك شبكات مسجلة حالياً',
            style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
          ),
          SizedBox(height: 8),
          Text(
            'يمكنك تسجيل شبكة جديدة عبر إدارة الشبكات',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;

  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: AppTheme.error),
          const SizedBox(height: 16),
          Text(
            'تعذر تحميل الشبكات: $message',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
