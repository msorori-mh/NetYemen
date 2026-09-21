import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_shell.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/customer_session_providers.dart';
import '../domain/pin_status.dart';
import 'pin_entry_screen.dart';
import 'pin_providers.dart';
import 'pin_setup_screen.dart';

/// بوّابة الرمز السري — تُقرر ما يراه المستخدم بعد تسجيل الدخول:
///
/// 1. [PinStatus.notSet]          → PinSetupScreen (إنشاء رمز).
/// 2. [PinStatus.setAndTrusted]   → AppShell مباشرة.
/// 3. [PinStatus.setAndUntrusted] → PinEntryScreen (تحقق من الرمز).
class PinGate extends ConsumerStatefulWidget {
  const PinGate({super.key});

  @override
  ConsumerState<PinGate> createState() => _PinGateState();
}

class _PinGateState extends ConsumerState<PinGate> {
  /// آخر خطأ منع تحديد حالة الرمز. غير فارغ ⇒ نعرض إعادة المحاولة،
  /// ولا ندخل التطبيق أبداً (البوّابة تفشل مُغلقة لا مفتوحة).
  Object? _error;

  @override
  void initState() {
    super.initState();
    _resolveGate();
  }

  Future<void> _resolveGate() async {
    if (_error != null) setState(() => _error = null);
    try {
      final user = ref.read(currentUserProvider);
      if (user == null) {
        // لا يوجد مستخدم (حالة غير متوقعة) — AppShell ستعالجها
        if (!mounted) return;
        _navigate(const AppShell());
        return;
      }

      final repo = ref.read(pinRepositoryProvider);
      final status = await repo.resolveStatus(user.id);

      if (!mounted) return;

      switch (status) {
        case PinStatus.notSet:
          _navigate(const PinSetupScreen());
        case PinStatus.setAndTrusted:
          _navigate(const AppShell());
        case PinStatus.setAndUntrusted:
          _navigate(const PinEntryScreen());
      }
    } catch (error) {
      // فشل مُغلق: لا نمنح الدخول عند تعذّر التحقق — نعرض إعادة المحاولة.
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  void _navigate(Widget destination) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => destination),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.primary,
              AppTheme.primary.withValues(alpha: 0.78),
            ],
          ),
        ),
        child: Center(
          child: _error == null
              ? const CircularProgressIndicator(
                  valueColor:
                      AlwaysStoppedAnimation<Color>(AppTheme.textOnPrimary),
                )
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.lock_outline,
                        color: AppTheme.textOnPrimary,
                        size: 48,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'تعذّر التحقق من رمز الحماية. تأكد من اتصالك ثم أعد المحاولة.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppTheme.textOnPrimary),
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        key: const Key('pin-gate-retry'),
                        onPressed: _resolveGate,
                        child: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
