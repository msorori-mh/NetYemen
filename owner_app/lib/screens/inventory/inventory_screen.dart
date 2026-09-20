// lib/screens/inventory/inventory_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/inventory_providers.dart';
import '../../providers/owner_providers.dart';
import '../../utils/app_theme.dart';
import 'card_upload_screen.dart';

/// F-OWN-04/05: شاشة المخزون — ملخّص المخزون + إحصائيات حالات الكروت + زر رفع دُفعة.
class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final networksAsync = ref.watch(ownedNetworksProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('المخزون'),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file),
            tooltip: 'رفع دُفعة كروت',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CardUploadScreen()),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CardUploadScreen()),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('رفع كروت'),
        backgroundColor: AppTheme.primary,
        foregroundColor: AppTheme.textOnPrimary,
      ),
      body: networksAsync.when(
        data: (networks) {
          if (networks.isEmpty) {
            return AppTheme.emptyState(
              icon: Icons.inventory_2_outlined,
              message: 'لا توجد شبكات مسجَّلة باسمك.',
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              for (final n in networks) {
                ref.invalidate(inventoryBalancesProvider(n.id));
                ref.invalidate(cardStateBreakdownProvider(n.id));
              }
              return ref.refresh(ownedNetworksProvider.future);
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: networks.length,
              itemBuilder: (context, index) {
                final network = networks[index];
                return _NetworkInventoryCard(
                  networkId: network.id,
                  networkName: network.commercialName,
                );
              },
            ),
          );
        },
        loading: () => AppTheme.loadingIndicator(),
        error: (_, __) => AppTheme.errorState(
          message: 'تعذّر تحميل الشبكات.',
          onRetry: () => ref.invalidate(ownedNetworksProvider),
        ),
      ),
    );
  }
}

/// بطاقة مخزون لشبكة واحدة — ملخّص الباقات + إحصائيات حالات الكروت.
class _NetworkInventoryCard extends ConsumerWidget {
  final String networkId;
  final String networkName;

  const _NetworkInventoryCard({
    required this.networkId,
    required this.networkName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balancesAsync = ref.watch(inventoryBalancesProvider(networkId));
    final breakdownAsync = ref.watch(cardStateBreakdownProvider(networkId));

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ───── اسم الشبكة ─────
            Row(
              children: [
                const Icon(Icons.wifi_rounded, color: AppTheme.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    networkName,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),

            const Divider(height: 24),

            // ───── إحصائيات حالات الكروت ─────
            breakdownAsync.when(
              data: (breakdown) {
                if (breakdown.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'لا توجد كروت بعد — ارفع دُفعة جديدة',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  );
                }
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: breakdown.entries.map((e) {
                    return _StateBadge(state: e.key, count: e.value);
                  }).toList(),
                );
              },
              loading: () => const SizedBox(
                height: 24,
                child: LinearProgressIndicator(),
              ),
              error: (_, __) => const Text(
                'تعذّر تحميل إحصائيات الكروت',
                style: TextStyle(color: AppTheme.error, fontSize: 13),
              ),
            ),

            const SizedBox(height: 12),

            // ───── ملخّص مخزون الباقات ─────
            balancesAsync.when(
              data: (balances) {
                if (balances.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'مخزون الباقات',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...balances.map((b) => _PackageBalanceRow(balance: b)),
                  ],
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ],
      ),
    );
  }
}

/// شارة حالة كرت مع العدد.
class _StateBadge extends StatelessWidget {
  final String state;
  final int count;

  const _StateBadge({required this.state, required this.count});

  Color _color() {
    switch (state) {
      case 'available':
        return AppTheme.accentDark;
      case 'sold':
        return AppTheme.info;
      case 'reserved':
        return AppTheme.warning;
      case 'quarantined':
      case 'invalidated':
        return AppTheme.error;
      default:
        return AppTheme.textMuted;
    }
  }

  String _label() {
    switch (state) {
      case 'available':
        return 'متاح';
      case 'sold':
        return 'مباع';
      case 'reserved':
        return 'محجوز';
      case 'quarantined':
        return 'معلّق';
      case 'invalidated':
        return 'ملغي';
      default:
        return state;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _color();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: TextStyle(fontWeight: FontWeight.bold, color: c, fontSize: 14),
          ),
          const SizedBox(width: 4),
          Text(
            _label(),
            style: TextStyle(color: c, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// صف مخزون باقة واحدة.
class _PackageBalanceRow extends StatelessWidget {
  final Map<String, dynamic> balance;

  const _PackageBalanceRow({required this.balance});

  @override
  Widget build(BuildContext context) {
    final available = balance['available_units'] ?? 0;
    final total = balance['total_units'] ?? 0;
    final isAvailable = balance['is_available'] == true;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            isAvailable ? Icons.check_circle : Icons.cancel,
            size: 14,
            color: isAvailable ? AppTheme.accentDark : AppTheme.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'الباقة: ${balance['package_id']?.toString().substring(0, 8) ?? '—'}…',
              style: const TextStyle(fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '$available / $total',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: available > 0 ? AppTheme.accentDark : AppTheme.error,
            ),
          ),
        ],
      ),
    );
  }
}
