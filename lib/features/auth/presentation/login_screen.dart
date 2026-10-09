import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../security/presentation/pin_gate.dart';
import '../../security/presentation/sign_in_gate.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/customer_auth.dart';
import 'customer_auth_providers.dart';
import 'otp_screen.dart';
import 'signup_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _hidePassword = true;
  bool _showPasswordSignIn = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    // This screen routes to the PIN gate itself; tell the app root so it does
    // not start a second gate for the same sign-in. Captured before the await
    // because `ref` must not be used once this screen is replaced.
    final signInClaim = ref.read(screenRoutedSignInProvider.notifier);
    // The navigator is captured too: a claimed sign-in must reach the PIN
    // gate even when this screen was closed while the request was in flight.
    final navigator = Navigator.of(context);
    signInClaim.state = true;
    try {
      final phone = normalizeYemeniPhone(_phoneController.text);
      await ref.read(customerAuthRepositoryProvider).signInWithPhonePassword(
            phone: phone,
            password: _passwordController.text,
          );
      if (!navigator.mounted) return;
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const PinGate()),
        (route) => false,
      );
    } on FormatException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('تعذر تسجيل الدخول. تحقق من رقم الهاتف وكلمة المرور.');
    } finally {
      signInClaim.state = false;
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      await ref.read(customerAuthRepositoryProvider).signInWithGoogle();
      // The browser returns through a deep link. The app root then sees the
      // "signed in" auth event and routes through the PIN gate.
    } catch (_) {
      _showError('تعذر بدء تسجيل الدخول بحساب Google.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendOtp() async {
    String phone;
    try {
      phone = normalizeYemeniPhone(_phoneController.text);
    } on FormatException catch (error) {
      _showError(error.message);
      return;
    }

    setState(() => _isLoading = true);
    try {
      await ref.read(customerAuthRepositoryProvider).signInWithPhone(phone);
      if (!mounted) return;
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => OTPScreen(phone: phone)));
    } catch (_) {
      _showError('تعذر إرسال رمز التحقق عبر واتساب حالياً. حاول بعد قليل.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    const Icon(
                      Icons.wifi_tethering_rounded,
                      size: 76,
                      color: AppTheme.primary,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'تسجيل الدخول',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'أدخل رقم جوالك المسجّل في واتساب، وسنرسل لك رمز تحقق من 6 أرقام',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 28),
                    TextFormField(
                      key: const Key('login-phone'),
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      textDirection: TextDirection.ltr,
                      decoration: const InputDecoration(
                        labelText: 'رقم الهاتف',
                        hintText: '77XXXXXXX',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                      validator: (value) {
                        try {
                          normalizeYemeniPhone(value ?? '');
                          return null;
                        } on FormatException catch (error) {
                          return error.message;
                        }
                      },
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton.icon(
                        key: const Key('login-whatsapp-otp'),
                        onPressed: _isLoading ? null : _sendOtp,
                        icon: const Icon(Icons.chat_outlined),
                        label: _isLoading && !_showPasswordSignIn
                            ? const SizedBox.square(
                                dimension: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('إرسال رمز التحقق عبر واتساب'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: OutlinedButton.icon(
                        key: const Key('login-google'),
                        onPressed: _isLoading ? null : _signInWithGoogle,
                        icon: const Icon(Icons.g_mobiledata, size: 28),
                        label: const Text('المتابعة بحساب Google'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      key: const Key('login-show-password'),
                      onPressed: _isLoading
                          ? null
                          : () => setState(
                                () => _showPasswordSignIn = !_showPasswordSignIn,
                              ),
                      child: Text(
                        _showPasswordSignIn
                            ? 'إخفاء الدخول بكلمة المرور'
                            : 'حسابات المختبرين: الدخول بكلمة المرور',
                      ),
                    ),
                    if (_showPasswordSignIn) ...[
                      const SizedBox(height: 8),
                      TextFormField(
                        key: const Key('login-password'),
                        controller: _passwordController,
                        obscureText: _hidePassword,
                        textDirection: TextDirection.ltr,
                        decoration: InputDecoration(
                          labelText: 'كلمة المرور',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            onPressed: () =>
                                setState(() => _hidePassword = !_hidePassword),
                            icon: Icon(
                              _hidePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        validator: (value) =>
                            (value ?? '').isEmpty ? 'كلمة المرور مطلوبة' : null,
                        onFieldSubmitted: (_) {
                          if (!_isLoading) _signIn();
                        },
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: OutlinedButton(
                          key: const Key('login-submit'),
                          onPressed: _isLoading ? null : _signIn,
                          child: _isLoading
                              ? const SizedBox.square(
                                  dimension: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('دخول بكلمة المرور'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        key: const Key('open-signup'),
                        onPressed: _isLoading
                            ? null
                            : () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const SignupScreen(),
                                  ),
                                ),
                        child: const Text('إنشاء حساب للمختبرين'),
                      ),
                    ],
                    const Divider(height: 28),
                    const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 20,
                          color: AppTheme.info,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'يصلك الرمز في محادثة واتساب على الرقم نفسه. لا تشارك الرمز مع أي شخص؛ فريق واصل نت لن يطلبه منك أبداً.',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
