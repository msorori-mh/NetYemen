// lib/features/wallet/presentation/wallet_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/app_config_provider.dart';
import '../../../core/widgets/customer_load_error.dart';
import '../../auth/presentation/customer_session_providers.dart';
import '../../auth/presentation/login_screen.dart';
import 'wallet_providers.dart';
import 'deposit_screen.dart';
import 'deposit_history_screen.dart';

class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final user = ref.watch(currentUserProvider);
    if (user == null && !config.isDemoMode) {
      return Scaffold(
        appBar: AppBar(title: const Text('المحفظة')),
        body: Directionality(
          textDirection: TextDirection.rtl,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 56),
                  const SizedBox(height: 16),
                  const Text(
                    'يرجى تسجيل الدخول لعرض المحفظة',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    ),
                    icon: const Icon(Icons.login),
                    label: const Text('تسجيل الدخول'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final walletAsync = ref.watch(walletSummaryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('المحفظة')),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(walletSummaryProvider);
            await ref.read(walletSummaryProvider.future);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16.0),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      const Text(
                        'رصيد المحفظة',
                        style: TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      walletAsync.when(
                        data: (wallet) => Text(
                          '${wallet.balance} ${wallet.currency}',
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        loading: () => const CircularProgressIndicator(),
                        error: (error, _) => CustomerLoadError(
                          error: error,
                          fallbackTitle: 'تعذر تحميل الرصيد',
                          compact: true,
                          onRetry: () => ref.invalidate(walletSummaryProvider),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DepositScreen()),
                ),
                icon: const Icon(Icons.add),
                label: const Text('طلب إيداع'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const DepositHistoryScreen(),
                  ),
                ),
                icon: const Icon(Icons.history),
                label: const Text('سجل الإيداعات'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
