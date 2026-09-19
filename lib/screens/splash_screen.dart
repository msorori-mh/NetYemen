// lib/screens/splash_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app/app_shell.dart';
import '../features/auth/presentation/customer_session_providers.dart';
import '../features/auth/presentation/login_screen.dart';
import '../utils/app_theme.dart';
import '../utils/constants.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    final user = ref.read(currentUserProvider);

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => user != null ? const AppShell() : const LoginScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primary,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.wifi_tethering_rounded,
              size: 80,
              color: AppTheme.textOnPrimary,
            ),
            const SizedBox(height: 20),
            const Text(
              AppConstants.appNameAr,
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: AppTheme.textOnPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'كروت الإنترنت في جيبك',
              style: TextStyle(
                fontSize: 16,
                color: AppTheme.textOnPrimary.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 40),
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.textOnPrimary),
            ),
          ],
        ),
      ),
    );
  }
}
