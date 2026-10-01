import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/owner_providers.dart';
import '../utils/app_theme.dart';
import 'pin_gate.dart';

class PinSetupScreen extends ConsumerStatefulWidget {
  const PinSetupScreen({super.key});

  @override
  ConsumerState<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends ConsumerState<PinSetupScreen> {
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();
  
  bool _isConfirmStep = false;
  bool _isLoading = false;
  String _errorMessage = '';

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _onDigitPressed(String digit) {
    if (_isLoading) return;
    final controller = _isConfirmStep ? _confirmController : _pinController;
    
    if (controller.text.length < 6) {
      setState(() {
        controller.text += digit;
        _errorMessage = '';
      });
      
      if (controller.text.length == 6) {
        if (!_isConfirmStep) {
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) setState(() => _isConfirmStep = true);
          });
        } else {
          _submitPin();
        }
      }
    }
  }

  void _onDeletePressed() {
    if (_isLoading) return;
    final controller = _isConfirmStep ? _confirmController : _pinController;
    if (controller.text.isNotEmpty) {
      setState(() {
        controller.text = controller.text.substring(0, controller.text.length - 1);
        _errorMessage = '';
      });
    } else if (_isConfirmStep) {
      setState(() {
        _isConfirmStep = false;
        _pinController.clear();
        _confirmController.clear();
        _errorMessage = '';
      });
    }
  }

  Future<void> _submitPin() async {
    if (_pinController.text != _confirmController.text) {
      setState(() {
        _errorMessage = 'رمز PIN غير متطابق. يرجى المحاولة مرة أخرى.';
        _isConfirmStep = false;
        _pinController.clear();
        _confirmController.clear();
      });
      return;
    }

    setState(() => _isLoading = true);
    
    try {
      final service = ref.read(ownerServiceProvider);
      await service.setAccountPin(_pinController.text);
      
      final user = ref.read(currentUserProvider);
      if (user != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('pin_trusted_${user.id}', '1');
      }
      
      ref.invalidate(hasAccountPinProvider);
      ref.invalidate(pinTrustedProvider);
    } on PostgrestException catch (e) {
      setState(() {
        _errorMessage = 'حدث خطأ: ${e.message}';
        _isConfirmStep = false;
        _pinController.clear();
        _confirmController.clear();
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'حدث خطأ غير متوقع';
        _isConfirmStep = false;
        _pinController.clear();
        _confirmController.clear();
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
  
  Widget _buildPinDots(String text) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (index) {
        final isFilled = index < text.length;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isFilled ? AppTheme.primary : AppTheme.textMuted.withValues(alpha: 0.3),
          ),
        );
      }),
    );
  }

  Widget _buildKeypad() {
    return Column(
      children: [
        for (var i = 0; i < 3; i++)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var j = 1; j <= 3; j++)
                _buildKeypadButton('${i * 3 + j}'),
            ],
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 80, height: 80),
            _buildKeypadButton('0'),
            _buildKeypadButton('del', icon: Icons.backspace_outlined),
          ],
        ),
      ],
    );
  }

  Widget _buildKeypadButton(String label, {IconData? icon}) {
    return Container(
      margin: const EdgeInsets.all(8),
      width: 64,
      height: 64,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            if (label == 'del') {
              _onDeletePressed();
            } else {
              _onDigitPressed(label);
            }
          },
          child: Center(
            child: icon != null
                ? Icon(icon, size: 28, color: AppTheme.textPrimary)
                : Text(
                    label,
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w500),
                  ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _isConfirmStep ? 'تأكيد رمز الدخول' : 'إعداد رمز الدخول';
    final subtitle = _isConfirmStep 
        ? 'الرجاء إدخال الرمز المكون من 6 أرقام مرة أخرى لتأكيده'
        : 'لحماية حسابك، يرجى إعداد رمز دخول مكون من 6 أرقام';
    final text = _isConfirmStep ? _confirmController.text : _pinController.text;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('رمز الدخول PIN'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 64, color: AppTheme.primary),
            const SizedBox(height: 24),
            Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.textSecondary)),
            ),
            const SizedBox(height: 48),
            
            _buildPinDots(text),
            
            const SizedBox(height: 24),
            if (_errorMessage.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(_errorMessage, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.error)),
              )
            else
              const SizedBox(height: 20),
              
            const SizedBox(height: 32),
            
            if (_isLoading)
              const CircularProgressIndicator()
            else
              _buildKeypad(),
              
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
