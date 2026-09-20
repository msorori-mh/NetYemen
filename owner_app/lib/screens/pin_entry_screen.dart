import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/owner_providers.dart';
import '../utils/app_theme.dart';
import 'pin_gate.dart';

class PinEntryScreen extends ConsumerStatefulWidget {
  final bool isAutoLock;

  const PinEntryScreen({super.key, this.isAutoLock = false});

  @override
  ConsumerState<PinEntryScreen> createState() => _PinEntryScreenState();
}

class _PinEntryScreenState extends ConsumerState<PinEntryScreen> {
  final _pinController = TextEditingController();
  
  bool _isLoading = false;
  String _errorMessage = '';

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  void _onDigitPressed(String digit) {
    if (_isLoading) return;
    
    if (_pinController.text.length < 6) {
      setState(() {
        _pinController.text += digit;
        _errorMessage = '';
      });
      
      if (_pinController.text.length == 6) {
        _submitPin();
      }
    }
  }

  void _onDeletePressed() {
    if (_isLoading) return;
    if (_pinController.text.isNotEmpty) {
      setState(() {
        _pinController.text = _pinController.text.substring(0, _pinController.text.length - 1);
        _errorMessage = '';
      });
    }
  }

  Future<void> _submitPin() async {
    setState(() => _isLoading = true);
    
    try {
      final service = ref.read(ownerServiceProvider);
      final isValid = await service.verifyAccountPin(_pinController.text);
      
      if (isValid) {
        final user = ref.read(currentUserProvider);
        if (user != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('pin_trusted_${user.id}', '1');
        }
        
        if (widget.isAutoLock) {
          if (mounted) Navigator.of(context).pop();
        } else {
          ref.invalidate(pinTrustedProvider);
        }
      } else {
        setState(() {
          _errorMessage = 'رمز PIN غير صحيح. يرجى المحاولة مرة أخرى.';
          _pinController.clear();
        });
      }
    } on PostgrestException catch (e) {
      setState(() {
        if (e.message.contains('PIN_LOCKED')) {
          _errorMessage = 'تم حظر الحساب مؤقتاً بسبب المحاولات الخاطئة. حاول بعد 15 دقيقة.';
        } else {
          _errorMessage = 'حدث خطأ: ${e.message}';
        }
        _pinController.clear();
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'حدث خطأ غير متوقع';
        _pinController.clear();
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _requestReset() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    try {
      final service = ref.read(ownerServiceProvider);
      await service.requestPinReset();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إرسال طلب إعادة التعيين للإدارة بنجاح')),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: ${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('حدث خطأ غير متوقع: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _signOut() {
    ref.read(ownerServiceProvider).signOut();
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
    return PopScope(
      canPop: !widget.isAutoLock, // Prevent going back if it's an auto-lock overlay
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: const Text('إدخال رمز الدخول'),
          centerTitle: true,
          automaticallyImplyLeading: false,
          actions: [
            if (!widget.isAutoLock)
              IconButton(
                icon: const Icon(Icons.logout),
                onPressed: _signOut,
                tooltip: 'تسجيل الخروج',
              ),
          ],
        ),
        body: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock, size: 64, color: AppTheme.primary),
              const SizedBox(height: 24),
              const Text('أدخل رمز الدخول (PIN)', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 32),
                child: Text('الرجاء إدخال رمز الدخول المكون من 6 أرقام', textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textSecondary)),
              ),
              const SizedBox(height: 48),
              
              _buildPinDots(_pinController.text),
              
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
                
              const SizedBox(height: 24),
              TextButton(
                onPressed: _isLoading ? null : _requestReset,
                child: const Text('نسيت رمز الدخول؟'),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
