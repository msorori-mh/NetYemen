import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/owner_providers.dart';
import 'splash_screen.dart'; // for RoleGate and SplashBranding
import 'pin_setup_screen.dart';
import 'pin_entry_screen.dart';

final pinTrustedProvider = FutureProvider<bool>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return false;
  final prefs = await SharedPreferences.getInstance();
  final isTrusted = prefs.getString('pin_trusted_${user.id}');
  return isTrusted == '1';
});

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
          error: (e, st) => Scaffold(body: Center(child: Text('خطأ: $e'))),
        );
      },
      loading: () => const SplashBranding(),
      error: (e, st) => Scaffold(body: Center(child: Text('خطأ: $e'))),
    );
  }
}
