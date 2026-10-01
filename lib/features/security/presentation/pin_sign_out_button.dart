import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/customer_auth_providers.dart';
import '../../auth/presentation/login_screen.dart';
import '../../notifications/presentation/fcm_token_service.dart';

/// مخرج من شاشات الرمز السري: بدونه يبقى المستخدم عالقاً إذا نسي الرمز أو
/// تعذّر التحقق. يسجّل الخروج ثم يعود إلى شاشة الدخول ويمسح كل المسارات.
class PinSignOutButton extends ConsumerStatefulWidget {
  const PinSignOutButton({super.key});

  @override
  ConsumerState<PinSignOutButton> createState() => _PinSignOutButtonState();
}

class _PinSignOutButtonState extends ConsumerState<PinSignOutButton> {
  bool _signingOut = false;

  Future<void> _signOut() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);

    try {
      try {
        await ref.read(fcmTokenServiceProvider).stop(deactivateToken: true);
      } catch (_) {
        // Token cleanup is best-effort and must never block account sign-out.
      }
      await ref.read(customerAuthRepositoryProvider).signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _signingOut = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تعذر تسجيل الخروج بأمان. تحقق من الاتصال ثم أعد المحاولة.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      key: const Key('pin-sign-out'),
      onPressed: _signingOut ? null : _signOut,
      icon: const Icon(Icons.logout_rounded, color: AppTheme.textOnPrimary),
      label: Text(
        'تسجيل الخروج',
        style: TextStyle(
          color: AppTheme.textOnPrimary.withValues(alpha: 0.8),
          fontSize: 14,
        ),
      ),
    );
  }
}
