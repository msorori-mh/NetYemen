import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_shell.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/customer_session_providers.dart';
import 'pin_providers.dart';

/// شاشة إدخال الرمز السري — تظهر على جهاز غير موثوق.
///
/// تحقق من الرمز → تأشير الجهاز كموثوق → AppShell.
/// رابط «نسيت الرمز؟» → request_pin_reset().
class PinEntryScreen extends ConsumerStatefulWidget {
  const PinEntryScreen({super.key});

  @override
  ConsumerState<PinEntryScreen> createState() => _PinEntryScreenState();
}

class _PinEntryScreenState extends ConsumerState<PinEntryScreen> {
  final _pinController = TextEditingController();
  final _pinFocus = FocusNode();

  bool _loading = false;
  String? _error;
  bool _resetRequested = false;

  @override
  void dispose() {
    _pinController.dispose();
    _pinFocus.dispose();
    super.dispose();
  }

  Future<void> _onSubmit() async {
    final pin = _pinController.text;
    if (pin.length != 6) {
      setState(() => _error = 'أدخل 6 أرقام');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final repo = ref.read(pinRepositoryProvider);
      final correct = await repo.verifyPin(pin);

      if (!mounted) return;

      if (correct) {
        // تأشير الجهاز كموثوق
        final user = ref.read(currentUserProvider);
        if (user != null) {
          await repo.trustDevice(user.id);
        }

        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AppShell()),
          (_) => false,
        );
      } else {
        setState(() {
          _loading = false;
          _error = 'الرمز السري غير صحيح';
          _pinController.clear();
        });
        _pinFocus.requestFocus();
      }
    } catch (e) {
      final msg = e.toString();
      setState(() {
        _loading = false;
        _pinController.clear();
        if (msg.contains('PIN_LOCKED')) {
          _error = 'محاولات كثيرة — حاول بعد 15 دقيقة';
        } else if (msg.contains('PIN_NOT_SET')) {
          _error = 'لا يوجد رمز سري — أعد تسجيل الدخول';
        } else {
          _error = 'حدث خطأ — حاول مرة أخرى';
        }
      });
      _pinFocus.requestFocus();
    }
  }

  Future<void> _onForgotPin() async {
    if (_resetRequested) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final repo = ref.read(pinRepositoryProvider);
      await repo.requestReset();

      if (!mounted) return;
      setState(() {
        _loading = false;
        _resetRequested = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('أُرسل طلب إعادة التعيين إلى المدير'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذّر إرسال طلب الإعادة — حاول لاحقاً';
      });
    }
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
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.lock_rounded,
                    size: 64,
                    color: AppTheme.textOnPrimary,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'أدخل الرمز السري',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textOnPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'أدخل رمزك السري المكوّن من 6 أرقام',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.textOnPrimary.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: 200,
                    child: TextField(
                      controller: _pinController,
                      focusNode: _pinFocus,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      textDirection: TextDirection.ltr,
                      maxLength: 6,
                      obscureText: true,
                      autofocus: true,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 12,
                        color: AppTheme.textPrimary,
                      ),
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        counterText: '',
                        filled: true,
                        fillColor: AppTheme.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        hintText: '••••••',
                        hintStyle: TextStyle(
                          fontSize: 28,
                          letterSpacing: 12,
                          color: AppTheme.textMuted.withValues(alpha: 0.5),
                        ),
                      ),
                      onChanged: (v) {
                        if (v.length == 6) _onSubmit();
                      },
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.error.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _error!,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (_loading)
                    const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppTheme.textOnPrimary,
                      ),
                    )
                  else ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _onSubmit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text(
                          'تحقق',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: _resetRequested ? null : _onForgotPin,
                      child: Text(
                        _resetRequested ? 'تم إرسال الطلب' : 'نسيت الرمز؟',
                        style: TextStyle(
                          color: _resetRequested
                              ? AppTheme.textOnPrimary.withValues(alpha: 0.5)
                              : AppTheme.textOnPrimary.withValues(alpha: 0.8),
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
