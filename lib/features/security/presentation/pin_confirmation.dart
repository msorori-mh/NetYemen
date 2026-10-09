import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config_provider.dart';
import '../../../core/utils/digit_input_formatter.dart';
import '../../../core/utils/digits.dart';
import 'pin_providers.dart';

/// Makes sure the server will accept a PIN-protected operation (a purchase,
/// revealing a card, issuing WASEL One credentials).
///
/// The server requires the account PIN to have been verified in this session
/// within a short window (`require_recent_account_pin`). When it has not, the
/// customer is asked for the PIN here. Returns `true` when the operation may
/// go ahead, `false` when the customer cancelled.
///
/// Demo builds have no backend and no PIN, so they always continue.
Future<bool> confirmAccountPin(BuildContext context, WidgetRef ref) async {
  if (ref.read(appConfigProvider).usesDemoData) return true;

  final repository = ref.read(pinRepositoryProvider);
  try {
    if (await repository.hasRecentVerification()) return true;
  } catch (_) {
    // Unknown state: ask for the PIN. The server checks the operation anyway.
  }
  if (!context.mounted) return false;

  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PinConfirmDialog(),
  );
  return confirmed == true;
}

/// Asks for the 6-digit account PIN and verifies it with the server.
/// Pops `true` once verified, `false` when cancelled.
class PinConfirmDialog extends ConsumerStatefulWidget {
  const PinConfirmDialog({super.key});

  @override
  ConsumerState<PinConfirmDialog> createState() => _PinConfirmDialogState();
}

class _PinConfirmDialogState extends ConsumerState<PinConfirmDialog> {
  final _controller = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    final pin = normalizeDigits(_controller.text.trim());
    if (pin.length != 6) {
      setState(() => _error = 'أدخل 6 أرقام');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final correct = await ref.read(pinRepositoryProvider).verifyPin(pin);
      if (!mounted) return;
      if (correct) {
        Navigator.of(context).pop(true);
        return;
      }
      setState(() {
        _loading = false;
        _error = 'الرمز السري غير صحيح';
        _controller.clear();
      });
    } catch (error) {
      if (!mounted) return;
      final message = error.toString();
      setState(() {
        _loading = false;
        _controller.clear();
        if (message.contains('PIN_LOCKED')) {
          _error = 'محاولات كثيرة — حاول بعد 15 دقيقة';
        } else if (message.contains('PIN_NOT_SET')) {
          _error = 'لا يوجد رمز سري لهذا الحساب — أعد تسجيل الدخول';
        } else {
          _error = 'تعذّر التحقق — تحقق من الاتصال وحاول مجدداً';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تأكيد بالرمز السري'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'لحماية رصيدك وكروتك، أدخل رمزك السري المكوّن من 6 أرقام للمتابعة.',
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('pin-confirm-field'),
            controller: _controller,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            textDirection: TextDirection.ltr,
            maxLength: 6,
            inputFormatters: const [
              LocalizedDigitsInputFormatter(maxLength: 6),
            ],
            decoration: InputDecoration(
              counterText: '',
              hintText: '••••••',
              errorText: _error,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('pin-confirm-cancel'),
          onPressed: _loading ? null : () => Navigator.of(context).pop(false),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          key: const Key('pin-confirm-submit'),
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('تأكيد'),
        ),
      ],
    );
  }
}
