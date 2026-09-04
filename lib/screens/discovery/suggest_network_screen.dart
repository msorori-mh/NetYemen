// lib/screens/discovery/suggest_network_screen.dart
//
// BR-NETWORK-009: submissions enter an unapproved lead queue and never grant
// public listing on their own.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';
import '../../utils/app_theme.dart';

class SuggestNetworkScreen extends ConsumerStatefulWidget {
  const SuggestNetworkScreen({super.key});

  @override
  ConsumerState<SuggestNetworkScreen> createState() =>
      _SuggestNetworkScreenState();
}

class _SuggestNetworkScreenState extends ConsumerState<SuggestNetworkScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _governorateController = TextEditingController();
  final _districtController = TextEditingController();
  final _cityController = TextEditingController();
  final _locationController = TextEditingController();
  final _notesController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _governorateController.dispose();
    _districtController.dispose();
    _cityController.dispose();
    _locationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final user = ref.read(currentUserProvider);
    if (user == null) {
      _showError('يرجى تسجيل الدخول أولاً');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final service = ref.read(supabaseServiceProvider);
      await service.submitNetworkAdditionLead(
        submittedBy: user.id,
        suggestedName: _nameController.text.trim(),
        governorate: _governorateController.text.trim(),
        district: _emptyToNull(_districtController.text),
        city: _emptyToNull(_cityController.text),
        locationText: _emptyToNull(_locationController.text),
        notes: _emptyToNull(_notesController.text),
      );

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('تم إرسال الاقتراح'),
          content: const Text(
            'شكراً لك! سيقوم فريقنا بمراجعة الطلب والتواصل مع الشبكة المقترحة',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
              child: const Text('حسناً'),
            ),
          ],
        ),
      );
    } catch (e) {
      _showError('تعذّر إرسال الاقتراح، حاول مرة أخرى');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String? _emptyToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('اقترح شبكة جديدة')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'ساعدنا في إضافة شبكة Wi-Fi غير مسجّلة لديك',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'اسم الشبكة أو المحل'),
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? 'مطلوب' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _governorateController,
              decoration: const InputDecoration(labelText: 'المحافظة'),
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? 'مطلوب' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _cityController,
              decoration: const InputDecoration(labelText: 'المدينة (اختياري)'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _districtController,
              decoration: const InputDecoration(labelText: 'الحي (اختياري)'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _locationController,
              decoration: const InputDecoration(
                labelText: 'وصف الموقع (اختياري)',
                hintText: 'مثال: بجانب مسجد النور',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notesController,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)'),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 54,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                child: _isSubmitting
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('إرسال الاقتراح'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
