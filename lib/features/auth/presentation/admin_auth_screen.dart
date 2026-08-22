import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../providers/app_providers.dart';
import '../../admin/presentation/admin_access.dart';
import '../../admin/presentation/admin_dashboard_screen.dart';
import '../data/admin_auth_repository.dart';
import 'admin_auth_providers.dart';

class AdminAuthCoordinator extends ConsumerStatefulWidget {
  const AdminAuthCoordinator({super.key});

  @override
  ConsumerState<AdminAuthCoordinator> createState() =>
      _AdminAuthCoordinatorState();
}

class _AdminAuthCoordinatorState extends ConsumerState<AdminAuthCoordinator> {
  StreamSubscription<AdminAuthEvent>? _authSubscription;
  bool _isPasswordRecovery = Uri.base.queryParameters['mode'] == 'recovery';
  bool _passwordUpdated = false;

  @override
  void initState() {
    super.initState();
    final config = ref.read(appConfigProvider);
    if (config.isConfigured) {
      _authSubscription = ref.read(adminAuthRepositoryProvider).events.listen(
        (event) {
          if (event == AdminAuthEvent.passwordRecovery && mounted) {
            setState(() => _isPasswordRecovery = true);
          }
        },
        onError: (Object _, StackTrace __) {
          debugPrint(
            'Admin auth event stream unavailable; using URL fallback.',
          );
        },
      );
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(appConfigProvider);
    if (config.isDemoMode) return const AdminDashboardScreen();

    if (_isPasswordRecovery) {
      return AdminPasswordRecoveryScreen(
        onCompleted: () {
          setState(() {
            _isPasswordRecovery = false;
            _passwordUpdated = true;
          });
        },
      );
    }

    final user = ref.watch(currentUserProvider);
    if (user == null) {
      return AdminEmailSignInScreen(
        initialMessage: _passwordUpdated
            ? 'تم تحديث كلمة المرور. سجّل الدخول بكلمة المرور الجديدة.'
            : null,
      );
    }

    final rolesAsync = ref.watch(currentUserRolesProvider);
    return rolesAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) => const _AdminSignedInAccessState(
        title: 'تعذر التحقق من الصلاحيات',
        message: 'أعد تسجيل الدخول بعد التحقق من الاتصال.',
      ),
      data: (roles) {
        if (AdminAccessPolicy.resolve(roles).isEmpty) {
          return const _AdminSignedInAccessState(
            title: 'الحساب غير مصرح',
            message:
                'تم تسجيل الدخول، لكن الحساب لا يملك أحد أدوار إدارة واصل نت.',
          );
        }
        return AdminDashboardScreen(
          onSignOut: () {
            unawaited(ref.read(adminAuthRepositoryProvider).signOut());
          },
        );
      },
    );
  }
}

class _AdminSignedInAccessState extends ConsumerWidget {
  final String title;
  final String message;

  const _AdminSignedInAccessState({required this.title, required this.message});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.no_accounts_outlined,
                      size: 56,
                      color: AppTheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(message, textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      onPressed: () =>
                          ref.read(adminAuthRepositoryProvider).signOut(),
                      icon: const Icon(Icons.logout),
                      label: const Text('تسجيل الخروج'),
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

class AdminEmailSignInScreen extends ConsumerStatefulWidget {
  final String? initialMessage;

  const AdminEmailSignInScreen({super.key, this.initialMessage});

  @override
  ConsumerState<AdminEmailSignInScreen> createState() =>
      _AdminEmailSignInScreenState();
}

class _AdminEmailSignInScreenState
    extends ConsumerState<AdminEmailSignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await ref.read(adminAuthRepositoryProvider).signIn(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );
    } on AuthException catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = _adminSignInErrorMessage(error);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage = 'تعذر الاتصال بخدمة تسجيل الدخول. أعد المحاولة.';
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AdminAuthScaffold(
      title: 'دخول لوحة الإدارة',
      subtitle: 'استخدم حسابًا إداريًا مصرحًا في واصل نت.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.initialMessage != null) ...[
              _StatusBanner(
                message: widget.initialMessage!,
                color: AppTheme.success,
              ),
              const SizedBox(height: 16),
            ],
            if (_errorMessage != null) ...[
              _StatusBanner(message: _errorMessage!, color: AppTheme.error),
              const SizedBox(height: 16),
            ],
            TextFormField(
              key: const Key('admin-email-field'),
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              textDirection: TextDirection.ltr,
              autofillHints: const [AutofillHints.username],
              decoration: const InputDecoration(
                labelText: 'البريد الإلكتروني',
                prefixIcon: Icon(Icons.email_outlined),
              ),
              validator: _validateEmail,
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('admin-password-field'),
              controller: _passwordController,
              obscureText: _obscurePassword,
              textDirection: TextDirection.ltr,
              autofillHints: const [AutofillHints.password],
              onFieldSubmitted: (_) {
                if (!_isLoading) _signIn();
              },
              decoration: InputDecoration(
                labelText: 'كلمة المرور',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: _obscurePassword
                      ? 'إظهار كلمة المرور'
                      : 'إخفاء كلمة المرور',
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                  icon: Icon(
                    _obscurePassword ? Icons.visibility : Icons.visibility_off,
                  ),
                ),
              ),
              validator: (value) =>
                  value == null || value.isEmpty ? 'أدخل كلمة المرور' : null,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const Key('admin-sign-in-button'),
              onPressed: _isLoading ? null : _signIn,
              icon: _isLoading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login),
              label: const Text('تسجيل الدخول'),
            ),
            const SizedBox(height: 8),
            TextButton(
              key: const Key('admin-forgot-password-button'),
              onPressed: _isLoading
                  ? null
                  : () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const AdminForgotPasswordScreen(),
                        ),
                      ),
              child: const Text('نسيت كلمة المرور؟'),
            ),
          ],
        ),
      ),
    );
  }
}

class AdminForgotPasswordScreen extends ConsumerStatefulWidget {
  const AdminForgotPasswordScreen({super.key});

  @override
  ConsumerState<AdminForgotPasswordScreen> createState() =>
      _AdminForgotPasswordScreenState();
}

class _AdminForgotPasswordScreenState
    extends ConsumerState<AdminForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isLoading = false;
  bool _emailSent = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendRecovery() async {
    if (!_formKey.currentState!.validate()) return;
    final config = ref.read(appConfigProvider);
    if (!config.hasValidAdminPasswordRecoveryRedirectUrl) {
      setState(() {
        _errorMessage = 'إعداد رابط استعادة لوحة الإدارة غير مكتمل.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final callbackUrl = config.adminPasswordRecoveryCallbackUrl!;
      await ref.read(adminAuthRepositoryProvider).requestPasswordRecovery(
            email: _emailController.text.trim(),
            redirectUrl: callbackUrl,
          );
      if (mounted) setState(() => _emailSent = true);
    } on AuthException catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = _adminRecoveryErrorMessage(error);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage = 'تعذر إرسال رابط الاستعادة. أعد المحاولة لاحقًا.';
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AdminAuthScaffold(
      title: 'استعادة كلمة المرور',
      subtitle: 'سنرسل رابطًا آمنًا إلى بريد الحساب الإداري.',
      showBackButton: true,
      child: _emailSent
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _StatusBanner(
                  message:
                      'إذا كان الحساب موجودًا فسيصلك رابط الاستعادة. افحص البريد غير المرغوب أيضًا.',
                  color: AppTheme.success,
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('العودة لتسجيل الدخول'),
                ),
              ],
            )
          : Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_errorMessage != null) ...[
                    _StatusBanner(
                      message: _errorMessage!,
                      color: AppTheme.error,
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextFormField(
                    key: const Key('admin-recovery-email-field'),
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textDirection: TextDirection.ltr,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'البريد الإلكتروني',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    validator: _validateEmail,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    key: const Key('admin-send-recovery-button'),
                    onPressed: _isLoading ? null : _sendRecovery,
                    icon: const Icon(Icons.mark_email_read_outlined),
                    label: Text(
                      _isLoading ? 'جارٍ الإرسال…' : 'إرسال رابط الاستعادة',
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class AdminPasswordRecoveryScreen extends ConsumerStatefulWidget {
  final VoidCallback onCompleted;

  const AdminPasswordRecoveryScreen({required this.onCompleted, super.key});

  @override
  ConsumerState<AdminPasswordRecoveryScreen> createState() =>
      _AdminPasswordRecoveryScreenState();
}

class _AdminPasswordRecoveryScreenState
    extends ConsumerState<AdminPasswordRecoveryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  Future<void> _updatePassword() async {
    if (!_formKey.currentState!.validate()) return;
    if (ref.read(currentUserProvider) == null) {
      setState(() {
        _errorMessage = 'رابط الاستعادة منتهي أو غير صالح. اطلب رابطًا جديدًا.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final repository = ref.read(adminAuthRepositoryProvider);
      await repository.updatePassword(_passwordController.text);
      await repository.signOut();
      if (mounted) widget.onCompleted();
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage = 'تعذر تحديث كلمة المرور. اطلب رابط استعادة جديدًا.';
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AdminAuthScaffold(
      title: 'تعيين كلمة مرور جديدة',
      subtitle: 'استخدم ثمانية أحرف على الأقل ولا تشاركها مع أي شخص.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_errorMessage != null) ...[
              _StatusBanner(message: _errorMessage!, color: AppTheme.error),
              const SizedBox(height: 16),
            ],
            TextFormField(
              key: const Key('admin-new-password-field'),
              controller: _passwordController,
              obscureText: true,
              textDirection: TextDirection.ltr,
              autofillHints: const [AutofillHints.newPassword],
              decoration: const InputDecoration(
                labelText: 'كلمة المرور الجديدة',
                prefixIcon: Icon(Icons.lock_reset_outlined),
              ),
              validator: (value) {
                if (value == null || value.length < 8) {
                  return 'استخدم ثمانية أحرف على الأقل';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('admin-confirm-password-field'),
              controller: _confirmationController,
              obscureText: true,
              textDirection: TextDirection.ltr,
              autofillHints: const [AutofillHints.newPassword],
              decoration: const InputDecoration(
                labelText: 'تأكيد كلمة المرور',
                prefixIcon: Icon(Icons.verified_user_outlined),
              ),
              validator: (value) => value != _passwordController.text
                  ? 'كلمتا المرور غير متطابقتين'
                  : null,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const Key('admin-update-password-button'),
              onPressed: _isLoading ? null : _updatePassword,
              icon: const Icon(Icons.password),
              label: Text(
                _isLoading ? 'جارٍ الحفظ…' : 'حفظ كلمة المرور الجديدة',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminAuthScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final bool showBackButton;

  const _AdminAuthScaffold({
    required this.title,
    required this.subtitle,
    required this.child,
    this.showBackButton = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: showBackButton
          ? AppBar(
              leading: BackButton(onPressed: () => Navigator.of(context).pop()),
            )
          : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        Icons.admin_panel_settings_outlined,
                        size: 64,
                        color: AppTheme.primary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        subtitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppTheme.textSecondary),
                      ),
                      const SizedBox(height: 24),
                      child,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final String message;
  final Color color;

  const _StatusBanner({required this.message, required this.color});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}

String? _validateEmail(String? value) {
  final email = value?.trim() ?? '';
  if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
    return 'أدخل بريدًا إلكترونيًا صحيحًا';
  }
  return null;
}

String _adminRecoveryErrorMessage(AuthException error) {
  final code = error.code?.toLowerCase();
  final message = error.message.toLowerCase();

  if (code == 'over_email_send_rate_limit' ||
      code == 'over_request_rate_limit' ||
      error.statusCode == '429' ||
      message.contains('rate limit') ||
      message.contains('too many requests') ||
      message.contains('429') ||
      message.contains('can only request this after') ||
      message.contains('for security purposes')) {
    return 'تم بلوغ حد إرسال رسائل الاستعادة. '
        'انتظر حتى مرور ساعة من آخر المحاولات ثم أعد الطلب مرة واحدة.';
  }

  if (code == 'email_address_not_authorized' ||
      message.contains('email address not authorized') ||
      message.contains('email address is not authorized')) {
    return 'البريد غير مصرح له عبر خدمة البريد الافتراضية في Supabase. '
        'أضف البريد إلى أعضاء المؤسسة أو فعّل SMTP مخصصًا.';
  }

  if (code == 'email_provider_disabled') {
    return 'تسجيل الدخول بالبريد معطل في Supabase Auth. فعّل Email provider.';
  }

  if (message.contains('redirect') &&
      (message.contains('allow') || message.contains('not allowed'))) {
    return 'رابط العودة غير مسموح في إعدادات Supabase Auth. '
        'أضف رابط لوحة الإدارة إلى Redirect URLs.';
  }

  if (message.contains('smtp') ||
      message.contains('email provider') ||
      message.contains('gomail')) {
    return 'تعذر تسليم بريد الاستعادة. '
        'تحقق من إعداد SMTP وسجلات Auth.';
  }

  return 'تعذر إرسال رابط الاستعادة. '
      'تحقق من إعدادات Auth ثم أعد المحاولة.';
}

String _adminSignInErrorMessage(AuthException error) {
  final code = error.code?.toLowerCase();
  final message = error.message.toLowerCase();

  if (code == 'email_not_confirmed' || message.contains('not confirmed')) {
    return 'البريد الإداري غير مؤكد. أكّد البريد في Supabase Auth ثم أعد الدخول.';
  }

  if (code == 'user_banned' || message.contains('banned')) {
    return 'الحساب الإداري موقوف. راجع حالة المستخدم في Supabase Auth.';
  }

  if (code == 'over_request_rate_limit' ||
      error.statusCode == '429' ||
      message.contains('too many requests')) {
    return 'تم بلوغ حد محاولات الدخول. انتظر عدة دقائق ثم حاول مرة واحدة.';
  }

  if (code == 'invalid_credentials' ||
      message.contains('invalid login credentials')) {
    return 'البريد أو كلمة المرور غير صحيحة.';
  }

  return 'تعذر تسجيل الدخول. تحقق من البريد وكلمة المرور وحالة الحساب.';
}
