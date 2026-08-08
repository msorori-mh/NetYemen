import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_theme.dart';
import '../features/network_discovery/presentation/home_screen.dart';
import '../features/network_discovery/presentation/networks_list_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/wallet/presentation/wallet_screen.dart';
import '../features/purchase/presentation/purchase_history_screen.dart';
import '../features/finance/presentation/deposit_review_queue_screen.dart';
import '../features/admin/presentation/admin_dashboard_screen.dart';
import '../providers/app_providers.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _currentIndex = 0;

  static const _customerDestinations = [
    NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home),
      label: 'الرئيسية',
    ),
    NavigationDestination(
      icon: Icon(Icons.wifi_outlined),
      selectedIcon: Icon(Icons.wifi),
      label: 'الشبكات',
    ),
    NavigationDestination(
      icon: Icon(Icons.account_balance_wallet_outlined),
      selectedIcon: Icon(Icons.account_balance_wallet),
      label: 'المحفظة',
    ),
    NavigationDestination(
      icon: Icon(Icons.receipt_long_outlined),
      selectedIcon: Icon(Icons.receipt_long),
      label: 'المشتريات',
    ),
    NavigationDestination(
      icon: Icon(Icons.person_outline),
      selectedIcon: Icon(Icons.person),
      label: 'الحساب',
    ),
  ];

  static const _customerScreens = [
    HomeScreen(),
    NetworksListScreen(),
    WalletScreen(),
    PurchaseHistoryScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final rolesAsync = ref.watch(currentUserRolesProvider);
    final roles = rolesAsync.value ?? [];
    final isFinanceOrAdmin = roles.contains('finance_officer') ||
        roles.contains('platform_admin') ||
        roles.contains('support_agent') ||
        roles.contains('system_auditor');

    final destinations = isFinanceOrAdmin
        ? [
            ..._customerDestinations,
            const NavigationDestination(
              icon: Icon(Icons.admin_panel_settings_outlined),
              selectedIcon: Icon(Icons.admin_panel_settings),
              label: 'الإدارة',
            ),
          ]
        : _customerDestinations;

    final screens = isFinanceOrAdmin
        ? [
            ..._customerScreens,
            const _FinanceAdminHomeScreen(),
          ]
        : _customerScreens;

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: screens.map((s) => s).toList(),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        destinations: destinations,
        backgroundColor: AppTheme.surface,
        indicatorColor: AppTheme.primary.withValues(alpha: 0.12),
      ),
    );
  }
}

class _FinanceAdminHomeScreen extends StatelessWidget {
  const _FinanceAdminHomeScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإدارة والمالية')),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.account_balance_wallet),
                title: const Text('قبول الإيداعات'),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const DepositReviewQueueScreen(),
                  ),
                ),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.dashboard),
                title: const Text('لوحة الإدارة'),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AdminDashboardScreen(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
