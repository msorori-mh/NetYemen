import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../features/network_discovery/presentation/network_discovery_providers.dart';
import '../../../providers/app_providers.dart';
import '../../../screens/auth/login_screen.dart';

/// Gates a screen or feature that requires an authenticated user.
///
/// In demo/unconfigured mode the gate is bypassed so the feature remains
/// testable. In configured mode, unauthenticated users see an Arabic,
/// RTL-friendly auth-required state with a real sign-in action.
class AuthRequiredGate extends ConsumerWidget {
  final Widget child;

  const AuthRequiredGate({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final user = ref.watch(currentUserProvider);

    if (config.isDemoMode || !config.isConfigured || user != null) {
      return child;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 64, color: AppTheme.textMuted),
            const SizedBox(height: 16),
            const Text(
              'تسجيل الدخول مطلوب',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'يجب تسجيل الدخول لعرض هذا القسم.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () => _navigateToSignIn(context),
                icon: const Icon(Icons.login),
                label: const Text('تسجيل الدخول'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToSignIn(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }
}
