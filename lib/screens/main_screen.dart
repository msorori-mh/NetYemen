// lib/screens/main_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';
import '../utils/app_theme.dart';
import 'home/home_screen.dart';
import 'wallet/wallet_screen.dart';
import 'purchases/purchases_screen.dart';
import 'profile/profile_screen.dart';

class MainScreen extends ConsumerWidget {
  const MainScreen({super.key});

  final List<Widget> _screens = const [
    HomeScreen(),
    WalletScreen(),
    PurchasesScreen(),
    ProfileScreen(),
  ];

  final List<BottomNavigationBarItem> _navItems = const [
    BottomNavigationBarItem(icon: Icon(Icons.wifi_rounded), label: 'الشبكات'),
    BottomNavigationBarItem(
      icon: Icon(Icons.account_balance_wallet_outlined),
      label: 'المحفظة',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.receipt_long_outlined),
      label: 'المشتريات',
    ),
    BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'حسابي'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedTab = ref.watch(selectedTabProvider);

    return Scaffold(
      body: IndexedStack(index: selectedTab, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: selectedTab,
        onTap: (index) => ref.read(selectedTabProvider.notifier).state = index,
        items: _navItems,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppTheme.primary,
        unselectedItemColor: AppTheme.textMuted,
        backgroundColor: AppTheme.surface,
        elevation: 8,
      ),
    );
  }
}
