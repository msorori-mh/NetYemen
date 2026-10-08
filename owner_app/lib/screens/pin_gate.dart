import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/owner_providers.dart';
import '../utils/app_theme.dart';
import 'splash_screen.dart'; // for RoleGate and SplashBranding
import 'pin_setup_screen.dart';
import 'pin_entry_screen.dart';

class PinGate extends ConsumerWidget {
  const PinGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPinAsync = ref.watch(hasAccountPinProvider);

    return hasPinAsync.when(
      data: (hasPin) {
        if (!hasPin) {
          return const PinSetupScreen();
        }

        final isTrustedAsync = ref.watch(pinTrustedProvider);
        return isTrustedAsync.when(
          data: (isTrusted) {
            if (isTrusted) {
              return const RoleGate();
            } else {
              return const PinEntryScreen(isAutoLock: false);
            }
          },
          loading: () => const SplashBranding(),
          // تعذّرت قراءة حالة القفل: نفشل مغلقين ونطلب الرمز.
          error: (e, st) => const PinEntryScreen(isAutoLock: false),
        );
      },
      loading: () => const SplashBranding(),
      error: (e, st) => _PinGateError(
        onRetry: () => ref.invalidate(hasAccountPinProvider),
      ),
    );
  }
}

class _PinGateError extends StatelessWidget {
  final VoidCallback onRetry;

  const _PinGateError({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Center(
        child: AppTheme.errorState(
          message: 'تعذّر التحقق من رمز الدخول. تحقّق من اتصالك بالإنترنت '
              'وحاول مرة أخرى.',
          onRetry: onRetry,
        ),
      ),
    );
  }
}
