
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/owner_providers.dart';
import '../../utils/app_theme.dart';
import 'network_detail_screen.dart';

class NetworksScreen extends ConsumerWidget {
  const NetworksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final networksAsyncValue = ref.watch(ownedNetworksProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('شبكاتي')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(ownedNetworksProvider.future),
        child: networksAsyncValue.when(
          data: (networks) {
            if (networks.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 80),
                  AppTheme.emptyState(
                    icon: Icons.wifi_off_rounded,
                    message: 'لا توجد شبكات مسجلة.',
                  ),
                ],
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: networks.length,
              itemBuilder: (context, index) {
                final network = networks[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: AppTheme.cardShadow,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                NetworkDetailScreen(network: network),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: AppTheme.primarySoft,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              alignment: Alignment.center,
                              child: const Icon(Icons.wifi_rounded,
                                  color: AppTheme.primary, size: 22),
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
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.textPrimary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    network.id.substring(0, 8),
                                    style: const TextStyle(
                                      color: AppTheme.textMuted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded,
                                color: AppTheme.textMuted),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
          loading: () => AppTheme.loadingIndicator(),
          error: (error, stack) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              const SizedBox(height: 80),
              AppTheme.errorState(
                message: 'تعذّر تحميل الشبكات',
                onRetry: () => ref.invalidate(ownedNetworksProvider),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
