import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_shell.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/customer_session_providers.dart';
import 'pin_providers.dart';

/// شاشة إنشاء الرمز السري (6 أرقام) — تظهر عند أول تسجيل دخول.
///
/// المراحل: إدخال → تأكيد → set_account_pin → تأشير الجهاز كموثوق → AppShell.
class PinSetupScreen extends ConsumerStatefulWidget {
  const PinSetupScreen({super.key});

  @override
  ConsumerState<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends ConsumerState<PinSetupScreen> {
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();
  final _pinFocus = FocusNode();
  final _confirmFocus = FocusNode();

  bool _isConfirming = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    _pinFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  Future<void> _onSubmit() async {
    final pin = _isConfirming ? _confirmController.text : _pinController.text;

    if (pin.length != 6) {
      setState(() => _error = 'أدخل 6 أرقام');
      return;
    }

    if (!_isConfirming) {
      // الانتقال لمرحلة التأكيد
      setState(() {
        _isConfirming = true;
        _error = null;
      });
      _confirmFocus.requestFocus();
      return;
    }

    // مرحلة التأكيد: تأكد من التطابق
    if (_confirmController.text != _pinController.text) {
      setState(() {
        _error = 'الرمز غير متطابق — أعد المحاولة';
        _isConfirming = false;
        _confirmController.clear();
        _pinController.clear();
      });
      _pinFocus.requestFocus();
      return;
    }

    // إرسال set_account_pin
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final repo = ref.read(pinRepositoryProvider);
      await repo.setPin(pin);

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
    } catch (e) {
      final msg = e.toString();
      setState(() {
        _loading = false;
        if (msg.contains('PIN_ALREADY_SET')) {
          _error = 'الرمز السري مُعيّن مسبقاً';
        } else if (msg.contains('INVALID_PIN')) {
          _error = 'الرمز يجب أن يكون 6 أرقام';
        } else {
          _error = 'حدث خطأ — حاول مرة أخرى';
        }
        _isConfirming = false;
        _confirmController.clear();
        _pinController.clear();
      });
      _pinFocus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _isConfirming ? 'تأكيد الرمز السري' : 'إنشاء رمز سري';
    final subtitle = _isConfirming
        ? 'أعد إدخال الرمز للتأكيد'
        : 'أنشئ رمزاً سرياً من 6 أرقام لتأمين حسابك';
    final controller = _isConfirming ? _confirmController : _pinController;

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
                  Icon(
                    _isConfirming
                        ? Icons.verified_user_rounded
                        : Icons.lock_outline_rounded,
                    size: 64,
                    color: AppTheme.textOnPrimary,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textOnPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
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
                      controller: controller,
                      focusNode: _isConfirming ? _confirmFocus : _pinFocus,
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
                  else
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _onSubmit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: Text(
                          _isConfirming ? 'تأكيد' : 'التالي',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  if (_isConfirming && !_loading) ...[
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _isConfirming = false;
                          _confirmController.clear();
                          _error = null;
                        });
                        _pinFocus.requestFocus();
                      },
                      child: Text(
                        'رجوع',
                        style: TextStyle(
                          color: AppTheme.textOnPrimary.withValues(alpha: 0.8),
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
