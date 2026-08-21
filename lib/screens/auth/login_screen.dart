import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_shell.dart';
import '../../features/auth/domain/customer_auth.dart';
import '../../providers/app_providers.dart';
import '../../utils/app_theme.dart';
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

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final phone = normalizeYemeniPhone(_phoneController.text);
      await ref.read(supabaseServiceProvider).signInWithPhonePassword(
            phone: phone,
            password: _passwordController.text,
          );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AppShell()),
        (route) => false,
      );
    } on FormatException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('تعذر تسجيل الدخول. تحقق من رقم الهاتف وكلمة المرور.');
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
      await ref.read(supabaseServiceProvider).signInWithPhone(phone);
      if (!mounted) return;
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => OTPScreen(phone: phone)));
    } catch (_) {
      _showError('تعذر إرسال الرمز حالياً. استخدم كلمة المرور للاختبار.');
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
                      'أدخل رقم الهاتف وكلمة المرور التي أنشأتها',
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
                    const SizedBox(height: 16),
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
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        key: const Key('login-submit'),
                        onPressed: _isLoading ? null : _signIn,
                        child: _isLoading
                            ? const SizedBox.square(
                                dimension: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('دخول'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
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
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _isLoading ? null : _sendOtp,
                      child: const Text('الدخول برمز SMS عند عودة الخدمة'),
                    ),
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
                            'استعادة كلمة المرور عبر الرسائل غير متاحة أثناء انقطاع الاتصالات. حسابات الاختبار تُدار بواسطة المشرف.',
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
