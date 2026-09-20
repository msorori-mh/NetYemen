// lib/screens/splash_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/app_theme.dart';
import '../providers/owner_providers.dart';
import 'auth/login_screen.dart';
import 'main_screen.dart';
import 'not_owner_screen.dart';
import 'create_first_network_screen.dart';
import 'pin_gate.dart';

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return authState.when(
      data: (state) {
        final session = state.session ??
            Supabase.instance.client.auth.currentSession;
        return session != null ? const PinGate() : const LoginScreen();
      },
      loading: () {
        final session = Supabase.instance.client.auth.currentSession;
        return session != null ? const PinGate() : const SplashBranding();
      },
      error: (err, stack) => Scaffold(
        backgroundColor: AppTheme.primary,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.white),
              const SizedBox(height: 16),
              const Text(
                'حدث خطأ في المصادقة',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(authStateProvider),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppTheme.primary,
                ),
                child: const Text('إعادة المحاولة'),
              )
            ],
          ),
        ),
      ),
    );
  }
}

class RoleGate extends ConsumerWidget {
  const RoleGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final networksAsync = ref.watch(ownedNetworksProvider);

    return networksAsync.when(
      data: (networks) {
        if (networks.isNotEmpty) {
          return const MainScreen();
        }
        
        final hasRoleAsync = ref.watch(hasNetworkOwnerRoleProvider);
        return hasRoleAsync.when(
          data: (hasRole) {
            if (hasRole) {
              return const CreateFirstNetworkScreen();
            } else {
              return const NotOwnerScreen();
            }
          },
          loading: () => const SplashBranding(),
          error: (err, stack) => Scaffold(
            backgroundColor: AppTheme.background,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: AppTheme.error),
                  const SizedBox(height: 16),
                  const Text(
                    'تعذّر التحقق من الصلاحيات',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => ref.invalidate(hasNetworkOwnerRoleProvider),
                    child: const Text('إعادة المحاولة'),
                  )
                ],
              ),
            ),
          ),
        );
      },
      loading: () => const SplashBranding(),
      error: (err, stack) => Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: AppTheme.error),
              const SizedBox(height: 16),
              const Text(
                'تعذّر تحميل شبكاتك',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 16),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(ownedNetworksProvider),
                child: const Text('إعادة المحاولة'),
              )
            ],
          ),
        ),
      ),
    );
  }
}

class SplashBranding extends StatelessWidget {
  const SplashBranding({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primary,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.storefront_rounded,
              size: 80,
              color: AppTheme.textOnPrimary,
            ),
            const SizedBox(height: 20),
            const Text(
              'واصل نت للملاك',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: AppTheme.textOnPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'إدارة شبكتك بفعالية',
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
