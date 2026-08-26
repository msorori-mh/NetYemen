import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../network_discovery/domain/entities.dart';
import '../../packages/presentation/network_packages_section.dart';

class NetworkDetailsScreen extends StatelessWidget {
  final NetworkEntity network;

  const NetworkDetailsScreen({super.key, required this.network});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(network.commercialName)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundColor: AppTheme.primary.withValues(
                          alpha: 0.1,
                        ),
                        child: Text(
                          network.commercialName.isNotEmpty
                              ? network.commercialName[0]
                              : '?',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              network.commercialName,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Row(
                              children: [
                                Icon(
                                  Icons.verified,
                                  color: AppTheme.accent,
                                  size: 16,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'شبكة معتمدة',
                                  style: TextStyle(
                                    color: AppTheme.accent,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (network.description != null &&
                      network.description!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      network.description!,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (network.locationText.isNotEmpty) ...[
            Card(
              child: ListTile(
                leading: const Icon(
                  Icons.location_on_outlined,
                  color: AppTheme.info,
                ),
                title: const Text('الموقع'),
                subtitle: Text(network.locationText),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (network.ssidAliases.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'أسماء الشبكة (SSID)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            ...network.ssidAliases.map(
              (alias) => Card(
                child: ListTile(
                  leading: const Icon(Icons.wifi, color: AppTheme.primary),
                  title: Text(alias.ssidDisplay),
                  subtitle: const Text('اسم البث'),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          NetworkPackagesSection(
            networkId: network.id,
            networkCommercialName: network.commercialName,
          ),
        ],
      ),
    );
  }
}
