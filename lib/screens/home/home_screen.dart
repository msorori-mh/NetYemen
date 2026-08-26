// lib/screens/home/home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/network_model.dart';
import '../../providers/app_providers.dart';
import '../../utils/app_theme.dart';
import '../../utils/constants.dart';
import 'network_detail_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final networksAsync = ref.watch(networksProvider);
    final searchQuery = ref.watch(networksSearchQueryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConstants.appNameAr),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              onChanged: (value) {
                ref.read(networksSearchQueryProvider.notifier).state = value;
              },
              decoration: InputDecoration(
                hintText: 'ابحث عن شبكة...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          ref.read(networksSearchQueryProvider.notifier).state =
                              '';
                        },
                      )
                    : null,
              ),
            ),
          ),

          // Networks List
          Expanded(
            child: networksAsync.when(
              data: (networks) {
                if (networks.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.wifi_off_rounded,
                          size: 64,
                          color: AppTheme.textMuted,
                        ),
                        SizedBox(height: 16),
                        Text('لا توجد شبكات متاحة'),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: networks.length,
                  itemBuilder: (context, index) {
                    final network = networks[index];
                    return NetworkCard(network: network);
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) =>
                  const Center(child: Text('حدث خطأ في تحميل الشبكات')),
            ),
          ),
        ],
      ),
    );
  }
}

class NetworkCard extends StatelessWidget {
  final Network network;

  const NetworkCard({super.key, required this.network});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => NetworkDetailScreen(network: network),
            ),
          );
        },
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
                      network.name.isNotEmpty ? network.name[0] : '?',
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
                          network.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          network.locationText,
                          style: const TextStyle(color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  if (network.isFeatured)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'مميز',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppTheme.accentDark,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
