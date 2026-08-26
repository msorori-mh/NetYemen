import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_shell.dart';
import '../../features/auth/domain/customer_auth.dart';
import '../../providers/app_providers.dart';
import '../../utils/app_theme.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _governorateController = TextEditingController(text: 'مأرب');
  final _cityController = TextEditingController(text: 'مدينة مأرب');
  final _inviteController = TextEditingController();

  RequestedAccountType _accountType = RequestedAccountType.customer;
  PilotLocation? _location;
  bool _locationConsent = false;
  bool _hidePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _governorateController.dispose();
    _cityController.dispose();
    _inviteController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (_location == null) {
      _showError('حدد موقعك التقريبي على الخريطة الاختبارية');
      return;
    }
    if (!_locationConsent) {
      _showError('يجب الموافقة على حفظ الموقع لأغراض الاختبار');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await ref.read(supabaseServiceProvider).registerTestAccount(
            TestAccountRegistration(
              fullName: _fullNameController.text,
              phone: _phoneController.text,
              password: _passwordController.text,
              requestedAccountType: _accountType,
              governorate: _governorateController.text,
              city: _cityController.text,
              latitude: _location!.latitude,
              longitude: _location!.longitude,
              inviteCode: _inviteController.text,
            ),
          );
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('تم إنشاء الحساب الاختباري'),
          content: Text(
            _accountType == RequestedAccountType.networkOwner
                ? 'تم تسجيل طلب صاحب الشبكة للمراجعة. الحساب لا يملك صلاحيات المالك حتى موافقة الإدارة والتحقق الفعلي.'
                : 'الحساب قيد التحقق ومخصص للاختبار أثناء تعذر رسائل الاتصالات.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('متابعة'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AppShell()),
        (route) => false,
      );
    } on FormatException catch (error) {
      _showError(error.message);
    } catch (error) {
      _showError(_friendlyRegistrationError(error));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _friendlyRegistrationError(Object error) {
    final message = error.toString();
    if (message.contains('ACCOUNT_EXISTS')) {
      return 'هذا الرقم مسجل مسبقاً. استخدم شاشة تسجيل الدخول.';
    }
    if (message.contains('INVALID_INVITE') ||
        message.contains('TESTER_NOT_ALLOWED')) {
      return 'رمز المختبر غير صحيح أو الرقم غير مصرح له.';
    }
    if (message.contains('TEST_ONBOARDING_EXPIRED') ||
        message.contains('TEST_ONBOARDING_DISABLED')) {
      return 'فترة إنشاء الحسابات الاختبارية متوقفة أو انتهت.';
    }
    return 'تعذر إنشاء الحساب. لم يتم حفظ حساب جزئي؛ حاول لاحقاً.';
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String? _required(String? value, String label, {int minimum = 2}) {
    if ((value ?? '').trim().length < minimum) return '$label مطلوب';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إنشاء حساب اختباري')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.warning.withValues(alpha: 0.35),
                  ),
                ),
                child: const Text(
                  'مسار مؤقت للمختبرين أثناء انقطاع الاتصالات. لا يُعد الرقم متحققاً عبر SMS أو واتساب، ولا يمنح اختيار صاحب شبكة أي صلاحية تلقائية.',
                  style: TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                key: const Key('signup-full-name'),
                controller: _fullNameController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'الاسم الكامل',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (value) => _required(value, 'الاسم', minimum: 3),
              ),
              const SizedBox(height: 14),
              TextFormField(
                key: const Key('signup-phone'),
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                textInputAction: TextInputAction.next,
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
              const SizedBox(height: 14),
              DropdownButtonFormField<RequestedAccountType>(
                key: const Key('signup-account-type'),
                initialValue: _accountType,
                decoration: const InputDecoration(
                  labelText: 'نوع الحساب المطلوب',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
                items: RequestedAccountType.values
                    .map(
                      (type) => DropdownMenuItem(
                        value: type,
                        child: Text(type.arabicLabel),
                      ),
                    )
                    .toList(),
                onChanged: _isLoading
                    ? null
                    : (value) =>
                        setState(() => _accountType = value ?? _accountType),
              ),
              if (_accountType == RequestedAccountType.networkOwner)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'سيُنشأ الحساب كزبون أولاً، ويظل طلب صاحب الشبكة قيد مراجعة الإدارة.',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              TextFormField(
                key: const Key('signup-password'),
                controller: _passwordController,
                obscureText: _hidePassword,
                textDirection: TextDirection.ltr,
                textInputAction: TextInputAction.next,
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
                validator: (value) => validateTestPassword(value ?? ''),
              ),
              const SizedBox(height: 14),
              TextFormField(
                key: const Key('signup-confirm-password'),
                controller: _confirmPasswordController,
                obscureText: true,
                textDirection: TextDirection.ltr,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'تأكيد كلمة المرور',
                  prefixIcon: Icon(Icons.lock_reset_outlined),
                ),
                validator: (value) => value != _passwordController.text
                    ? 'كلمتا المرور غير متطابقتين'
                    : null,
              ),
              const SizedBox(height: 20),
              Text(
                'الموقع',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      key: const Key('signup-governorate'),
                      controller: _governorateController,
                      decoration: const InputDecoration(labelText: 'المحافظة'),
                      validator: (value) => _required(value, 'المحافظة'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      key: const Key('signup-city'),
                      controller: _cityController,
                      decoration: const InputDecoration(labelText: 'المدينة'),
                      validator: (value) => _required(value, 'المدينة'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              OfflinePilotLocationPicker(
                value: _location,
                onChanged: (value) => setState(() => _location = value),
              ),
              CheckboxListTile(
                key: const Key('signup-location-consent'),
                value: _locationConsent,
                onChanged: _isLoading
                    ? null
                    : (value) =>
                        setState(() => _locationConsent = value ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'أوافق على حفظ هذا الموقع بشكل خاص لأغراض الاختبار',
                  style: TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                key: const Key('signup-invite'),
                controller: _inviteController,
                obscureText: true,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'رمز المختبر',
                  prefixIcon: Icon(Icons.vpn_key_outlined),
                ),
                validator: (value) =>
                    _required(value, 'رمز المختبر', minimum: 12),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 54,
                child: ElevatedButton(
                  key: const Key('signup-submit'),
                  onPressed: _isLoading ? null : _register,
                  child: _isLoading
                      ? const SizedBox.square(
                          dimension: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('إنشاء الحساب والدخول'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PilotLocation {
  final double latitude;
  final double longitude;

  const PilotLocation({required this.latitude, required this.longitude});
}

class OfflinePilotLocationPicker extends StatelessWidget {
  static const _minimumLatitude = 14.0;
  static const _maximumLatitude = 17.0;
  static const _minimumLongitude = 44.0;
  static const _maximumLongitude = 47.0;

  final PilotLocation? value;
  final ValueChanged<PilotLocation> onChanged;

  const OfflinePilotLocationPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'اضغط لوضع علامة تقريبية (يعمل دون اتصال)',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 8),
        AspectRatio(
          aspectRatio: 1.7,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                key: const Key('offline-location-picker'),
                onTapDown: (details) {
                  final x = (details.localPosition.dx / constraints.maxWidth)
                      .clamp(0.0, 1.0)
                      .toDouble();
                  final y = (details.localPosition.dy / constraints.maxHeight)
                      .clamp(0.0, 1.0)
                      .toDouble();
                  onChanged(
                    PilotLocation(
                      latitude: _maximumLatitude -
                          y * (_maximumLatitude - _minimumLatitude),
                      longitude: _minimumLongitude +
                          x * (_maximumLongitude - _minimumLongitude),
                    ),
                  );
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CustomPaint(painter: _OfflineMapPainter()),
                      const Positioned(
                        top: 10,
                        right: 12,
                        child: _MapLabel('شمال'),
                      ),
                      const Positioned(
                        bottom: 10,
                        left: 12,
                        child: _MapLabel('نطاق مأرب الاختباري'),
                      ),
                      if (value != null)
                        Positioned(
                          left: _xFor(value!.longitude) * constraints.maxWidth -
                              18,
                          top: _yFor(value!.latitude) * constraints.maxHeight -
                              36,
                          child: const Icon(
                            Icons.location_pin,
                            size: 40,
                            color: AppTheme.error,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value == null
              ? 'لم يتم تحديد الموقع بعد'
              : 'الموقع التقريبي: ${value!.latitude.toStringAsFixed(5)}, ${value!.longitude.toStringAsFixed(5)}',
          key: const Key('selected-location-text'),
          textDirection: TextDirection.ltr,
          style: TextStyle(
            color: value == null ? AppTheme.error : AppTheme.textSecondary,
            fontSize: 12,
          ),
        ),
        const Text(
          'هذه أداة مكانية تقريبية للاختبار وليست خريطة عنوان رسمية.',
          style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
        ),
      ],
    );
  }

  double _xFor(double longitude) => ((longitude - _minimumLongitude) /
          (_maximumLongitude - _minimumLongitude))
      .clamp(0.0, 1.0)
      .toDouble();

  double _yFor(double latitude) =>
      ((_maximumLatitude - latitude) / (_maximumLatitude - _minimumLatitude))
          .clamp(0.0, 1.0)
          .toDouble();
}

class _MapLabel extends StatelessWidget {
  final String text;

  const _MapLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Text(text, style: const TextStyle(fontSize: 10)),
      ),
    );
  }
}

class _OfflineMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()..color = const Color(0xFFE8E2CF);
    canvas.drawRect(Offset.zero & size, background);

    final terrain = Paint()
      ..color = const Color(0xFFD3C69F)
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(0, size.height * 0.72)
      ..quadraticBezierTo(
        size.width * 0.22,
        size.height * 0.46,
        size.width * 0.42,
        size.height * 0.62,
      )
      ..quadraticBezierTo(
        size.width * 0.68,
        size.height * 0.84,
        size.width,
        size.height * 0.50,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, terrain);

    final road = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke;
    canvas.drawPath(
      Path()
        ..moveTo(0, size.height * 0.55)
        ..cubicTo(
          size.width * 0.32,
          size.height * 0.40,
          size.width * 0.56,
          size.height * 0.72,
          size.width,
          size.height * 0.32,
        ),
      road,
    );

    final grid = Paint()
      ..color = AppTheme.primary.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    for (var index = 1; index < 6; index += 1) {
      canvas.drawLine(
        Offset(size.width * index / 6, 0),
        Offset(size.width * index / 6, size.height),
        grid,
      );
    }
    for (var index = 1; index < 4; index += 1) {
      canvas.drawLine(
        Offset(0, size.height * index / 4),
        Offset(size.width, size.height * index / 4),
        grid,
      );
    }

    final border = Paint()
      ..color = AppTheme.border
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawRect(Offset.zero & size, border);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
