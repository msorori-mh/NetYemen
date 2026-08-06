import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../network_discovery/presentation/network_discovery_providers.dart';
import '../../network_requests/presentation/network_request_providers.dart';

class AddRequestScreen extends ConsumerStatefulWidget {
  const AddRequestScreen({super.key});

  @override
  ConsumerState<AddRequestScreen> createState() => _AddRequestScreenState();
}

class _AddRequestScreenState extends ConsumerState<AddRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _ssidController = TextEditingController();
  final _nameController = TextEditingController();
  final _governorateController = TextEditingController();
  final _cityController = TextEditingController();
  final _districtController = TextEditingController();
  final _notesController = TextEditingController();

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final prefillSsid = ref.read(selectedScanSsidProvider);
      if (prefillSsid != null && _ssidController.text.isEmpty) {
        _ssidController.text = prefillSsid;
      }
    });
  }

  @override
  void dispose() {
    _ssidController.dispose();
    _nameController.dispose();
    _governorateController.dispose();
    _cityController.dispose();
    _districtController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      _showAuthRequired();
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final notifier = ref.read(submitRequestNotifierProvider);
      await notifier.submit(
        observedSsidDisplay: _ssidController.text.trim(),
        proposedNetworkName: _nameController.text.trim().isNotEmpty
            ? _nameController.text.trim()
            : null,
        governorate: _governorateController.text.trim().isNotEmpty
            ? _governorateController.text.trim()
            : null,
        city: _cityController.text.trim().isNotEmpty
            ? _cityController.text.trim()
            : null,
        district: _districtController.text.trim().isNotEmpty
            ? _districtController.text.trim()
            : null,
        notes: _notesController.text.trim().isNotEmpty
            ? _notesController.text.trim()
            : null,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إرسال الطلب بنجاح')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل إرسال الطلب: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showAuthRequired() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تسجيل الدخول مطلوب'),
        content: const Text('يجب تسجيل الدخول لإرسال طلب إضافة شبكة.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('حسناً'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('طلب إضافة شبكة'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _ssidController,
              decoration: const InputDecoration(
                labelText: 'اسم الشبكة (SSID) *',
                hintText: 'مثال: MyNetwork_WiFi',
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'يرجى إدخال اسم الشبكة';
                }
                if (v.trim().length > 64) {
                  return 'اسم الشبكة يجب ألا يتجاوز 64 حرف';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'الاسم المقترح للشبكة',
                hintText: 'مثال: شبكة صنعاء السريعة',
              ),
              maxLength: 100,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _governorateController,
              decoration: const InputDecoration(
                labelText: 'المحافظة',
                hintText: 'مثال: أمانة العاصمة',
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _cityController,
              decoration: const InputDecoration(
                labelText: 'المدينة',
                hintText: 'مثال: صنعاء',
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _districtController,
              decoration: const InputDecoration(
                labelText: 'الحي',
                hintText: 'مثال: الوحدة',
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'ملاحظات',
                hintText: 'أي معلومات إضافية عن الشبكة...',
              ),
              maxLength: 500,
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('إرسال الطلب'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
