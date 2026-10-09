import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../security/presentation/pin_gate.dart';
import '../../security/presentation/sign_in_gate.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/digit_input_formatter.dart';
import '../../../core/utils/digits.dart';
import 'customer_auth_providers.dart';

class OTPScreen extends ConsumerStatefulWidget {
  final String phone;

  const OTPScreen({super.key, required this.phone});

  /// Seconds the customer must wait before asking for another code.
  static const int resendCooldownSeconds = 60;

  @override
  ConsumerState<OTPScreen> createState() => _OTPScreenState();
}

class _OTPScreenState extends ConsumerState<OTPScreen> {
  final _otpController = TextEditingController();
  bool _isLoading = false;
  bool _isResending = false;
  Timer? _cooldownTimer;
  int _cooldownRemaining = 0;

  @override
  void initState() {
    super.initState();
    // A code was sent just before this screen opened.
    _startCooldown();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _otpController.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    _cooldownRemaining = OTPScreen.resendCooldownSeconds;
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _cooldownRemaining -= 1;
        if (_cooldownRemaining <= 0) {
          _cooldownRemaining = 0;
          timer.cancel();
        }
      });
    });
  }

  Future<void> _verifyOTP() async {
    final otp = normalizeDigits(_otpController.text.trim());
    if (otp.length != 6) {
      _showError('يرجى إدخال الرمز كاملاً');
      return;
    }

    setState(() => _isLoading = true);

    // This screen routes to the PIN gate itself, so it claims the sign-in
    // (see screenRoutedSignInProvider).
    final signInClaim = ref.read(screenRoutedSignInProvider.notifier);
    // The navigator is captured too: a claimed sign-in must reach the PIN
    // gate even when this screen was closed while the request was in flight.
    final navigator = Navigator.of(context);
    signInClaim.state = true;
    try {
      final repository = ref.read(customerAuthRepositoryProvider);
      final response = await repository.verifyOtp(widget.phone, otp);

      if (response.user != null) {
        // V1 identity is provisioned automatically by the Supabase auth trigger
        // public.handle_new_user into public.profiles / public.user_roles.
        // No client-side upsert to public.users is required or permitted.
        if (!navigator.mounted) return;
        navigator.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const PinGate()),
          (route) => false,
        );
      } else {
        _showError('رمز التحقق غير صحيح');
      }
    } catch (_) {
      _showError('رمز التحقق غير صحيح');
    } finally {
      signInClaim.state = false;
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _resendOTP() async {
    if (_isResending || _cooldownRemaining > 0) return;
    setState(() => _isResending = true);

    try {
      await ref
          .read(customerAuthRepositoryProvider)
          .signInWithPhone(widget.phone);
      if (!mounted) return;
      _otpController.clear();
      setState(_startCooldown);
      _showMessage('أُرسل رمز جديد إلى واتساب على رقمك.');
    } catch (_) {
      _showError('تعذر إرسال الرمز حالياً. حاول بعد قليل.');
    } finally {
      if (mounted) {
        setState(() => _isResending = false);
      }
    }
  }

  void _showError(String message) => _showMessage(message);

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final canResend = !_isResending && !_isLoading && _cooldownRemaining == 0;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'التحقق من الرقم',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'أدخل الرمز المرسل عبر واتساب إلى ${widget.phone}',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 40),
            TextField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 6,
              inputFormatters: const [
                LocalizedDigitsInputFormatter(maxLength: 6),
              ],
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: 8,
              ),
              decoration: const InputDecoration(
                hintText: '000000',
                counterText: '',
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _verifyOTP,
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('تحقق'),
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              key: const Key('otp-resend'),
              onPressed: canResend ? _resendOTP : null,
              child: Text(
                _cooldownRemaining > 0
                    ? 'إعادة إرسال الرمز بعد $_cooldownRemaining ثانية'
                    : 'إعادة إرسال الرمز',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
