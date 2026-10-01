import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../purchase/presentation/purchase_confirmation_screen.dart';
import '../domain/entities.dart';
import 'package_providers.dart';

class NetworkPackagesSection extends ConsumerWidget {
  final String networkId;
  final String? networkCommercialName;

  const NetworkPackagesSection({
    super.key,
    required this.networkId,
    this.networkCommercialName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packagesAsync = ref.watch(publicPackagesProvider(networkId));

    return packagesAsync.when(
      data: (packages) => _buildContent(context, packages),
      loading: () => const _LoadingState(),
      error: (_, __) => _ErrorState(
        onRetry: () => ref.invalidate(publicPackagesProvider(networkId)),
      ),
    );
  }

  Widget _buildContent(BuildContext context, List<NetworkPackage> packages) {
    if (packages.isEmpty) {
      return const _EmptyState();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'الباقات المتاحة',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        ...packages.map(
          (pkg) => _PackageCard(
            package: pkg,
            networkCommercialName: networkCommercialName,
          ),
        ),
      ],
    );
  }
}

class _PackageCard extends ConsumerWidget {
  final NetworkPackage package;
  final String? networkCommercialName;

  const _PackageCard({required this.package, this.networkCommercialName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balanceAsync = ref.watch(packageBalanceProvider(package.id));
    final balance = balanceAsync.valueOrNull;
    final isAvailable = balance != null && !balance.isOutOfStock;
    final buttonLabel = balanceAsync.isLoading
        ? 'التحقق من التوفر...'
        : isAvailable
            ? 'شراء'
            : 'غير متوفر';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    package.name,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _AvailabilityBadge(balanceAsync: balanceAsync),
              ],
            ),
            if (package.description != null &&
                package.description!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                package.description!,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                _MetaChip(
                  icon: Icons.timer_outlined,
                  label: package.durationText.isEmpty
                      ? 'غير محدد'
                      : package.durationText,
                ),
                if (package.speedMbps != null) ...[
                  const SizedBox(width: 8),
                  _MetaChip(
                    icon: Icons.speed_outlined,
                    label: '${package.speedMbps} Mbps',
                  ),
                ],
                const Spacer(),
                Text(
                  package.displayPrice,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isAvailable
                    ? () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => PurchaseConfirmationScreen(
                              package: package,
                              networkName: networkCommercialName ?? 'شبكة',
                            ),
                          ),
                        )
                    : null,
                child: balanceAsync.isLoading
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 8),
                          Text('التحقق من التوفر...'),
                        ],
                      )
                    : Text(buttonLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvailabilityBadge extends StatelessWidget {
  final AsyncValue<PackageInventoryBalance?> balanceAsync;

  const _AvailabilityBadge({required this.balanceAsync});

  @override
  Widget build(BuildContext context) {
    return balanceAsync.when(
      data: (balance) {
        final isAvailable = balance != null && !balance.isOutOfStock;
        return _StatusBadge(
          label: isAvailable ? 'متوفر' : 'غير متوفر',
          isAvailable: isAvailable,
        );
      },
      loading: () => const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (_, __) => const _StatusBadge(
        label: 'تعذر التحقق',
        isAvailable: false,
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final bool isAvailable;

  const _StatusBadge({required this.label, required this.isAvailable});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isAvailable
            ? AppTheme.accent.withValues(alpha: 0.1)
            : AppTheme.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isAvailable ? AppTheme.accent : AppTheme.error,
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppTheme.textSecondary),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
      ],
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(
              Icons.inventory_2_outlined,
              color: AppTheme.textSecondary,
              size: 40,
            ),
            SizedBox(height: 12),
            Text(
              'لا توجد باقات متاحة حالياً',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;

  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(Icons.error_outline, color: AppTheme.error, size: 40),
            const SizedBox(height: 12),
            const Text(
              'تعذر تحميل الباقات. تحقق من اتصال الإنترنت ثم حاول مجددًا.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}
