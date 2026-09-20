// lib/screens/dashboard/dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/owned_network_model.dart';
import '../../providers/owner_providers.dart';
import '../../utils/app_theme.dart';
import '../auth/login_screen.dart';

/// الشاشة الرئيسية: قائمة شبكات المالك الحالي عبر [ownedNetworksProvider].
///
/// هذا هو المحتوى الحقيقي الوحيد في هذه الموجة؛ باقي التبويبات شاشات مؤقتة.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    await ref.read(ownerServiceProvider).signOut();
    if (!context.mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final networksAsync = ref.watch(ownedNetworksProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('شبكاتي'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'تسجيل الخروج',
            onPressed: () => _signOut(context, ref),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(ownedNetworksProvider.future),
        child: networksAsync.when(
          data: (networks) {
            if (networks.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 80),
                  AppTheme.emptyState(
                    icon: Icons.wifi_off_rounded,
                    message: 'لا توجد شبكات مسجَّلة باسمك بعد',
                  ),
                ],
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: networks.length,
              itemBuilder: (context, index) =>
                  _NetworkCard(network: networks[index]),
            );
          },
          loading: () => AppTheme.loadingIndicator(),
          error: (_, __) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              const SizedBox(height: 80),
              AppTheme.errorState(
                message: 'تعذّر تحميل شبكاتك. اسحب للأسفل للمحاولة مرة أخرى.',
                onRetry: () => ref.invalidate(ownedNetworksProvider),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NetworkCard extends StatelessWidget {
  final OwnedNetwork network;

  const _NetworkCard({required this.network});

  Color _statusColor() {
    switch (network.status) {
      case 'active':
        return AppTheme.success;
      case 'suspended':
      case 'rejected':
        return AppTheme.error;
      default:
        return AppTheme.warning;
    }
  }

  String _statusText() {
    switch (network.status) {
      case 'active':
        return 'نشطة';
      case 'suspended':
        return 'موقوفة';
      case 'rejected':
        return 'مرفوضة';
      case 'pending_approval':
        return 'قيد الاعتماد';
      default:
        return network.status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.cardShadow,
      ),
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
            child: Text(
              network.commercialName.isNotEmpty
                  ? network.commercialName[0]
                  : '؟',
              style: const TextStyle(
                color: AppTheme.primary,
                fontWeight: FontWeight.bold,
                fontSize: 18,
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
                    Flexible(
                      child: Text(
                        network.commercialName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (network.isVerified) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.verified_rounded, size: 18,
                          color: AppTheme.primary),
                    ],
                  ],
                ),
                if (network.locationText.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    network.locationText,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
                if (network.status == 'pending_approval') ...[
                  const SizedBox(height: 4),
                  const Text(
                    'الشبكة قيد الاعتماد من الإدارة، ولن تظهر للعملاء بعد.',
                    style: TextStyle(color: AppTheme.warning, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          AppTheme.statusChip(
            _statusText(),
            color: _statusColor().withValues(alpha: 0.12),
            textColor: _statusColor(),
          ),
        ],
      ),
    );
  }
}
