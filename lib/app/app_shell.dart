import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../features/network_discovery/presentation/home_screen.dart';
import '../features/network_discovery/presentation/networks_list_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/wallet/presentation/wallet_screen.dart';
import '../features/purchase/presentation/purchase_history_screen.dart';
import '../features/notifications/presentation/fcm_token_service.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
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

  List<Widget> get _customerScreens => [
        HomeScreen(
          onSelectDestination: (index) {
            setState(() => _currentIndex = index);
          },
        ),
        const NetworksListScreen(),
        const WalletScreen(),
        const PurchaseHistoryScreen(),
        const ProfileScreen(),
      ];

  @override
  Widget build(BuildContext context) {
    return FcmTokenInitializer(
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: _customerScreens,
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) {
            setState(() => _currentIndex = index);
          },
          destinations: _customerDestinations,
          backgroundColor: AppTheme.surface,
          indicatorColor: AppTheme.primary.withValues(alpha: 0.12),
        ),
      ),
    );
  }
}
