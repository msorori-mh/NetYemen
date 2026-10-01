import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/location/yemen_location_catalog.dart';
import '../../../core/theme/app_theme.dart';
import '../data/customer_profile_repository.dart';
import '../domain/customer_profile.dart';

class ProfileEditScreen extends ConsumerStatefulWidget {
  final CustomerProfile profile;

  const ProfileEditScreen({super.key, required this.profile});

  @override
  ConsumerState<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _cityController;
  late String _governorate;
  bool _submitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.profile.fullName ?? '',
    );
    _cityController = TextEditingController(text: widget.profile.city ?? '');
    _governorate = widget.profile.governorate?.trim().isNotEmpty == true
        ? widget.profile.governorate!.trim()
        : YemenLocationCatalog.governorates.first;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  String? _validateRequired(
    String? value,
    String label, {
    required int min,
    required int max,
  }) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) return '$label مطلوب';
    if (normalized.length < min) return '$label قصير جدًا';
    if (normalized.length > max) return '$label يتجاوز الحد المسموح';
    return null;
  }

  Future<void> _save() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      await ref.read(customerProfileRepositoryProvider).updateMyProfile(
            CustomerProfileUpdate(
              fullName: _nameController.text,
              governorate: _governorate,
              city: _cityController.text,
            ),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'تعذر حفظ الملف الشخصي. تحقق من الاتصال ثم أعد المحاولة.';
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final governorates = YemenLocationCatalog.optionsIncluding(_governorate);
    return Scaffold(
      appBar: AppBar(title: const Text('تعديل الملف الشخصي')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              TextFormField(
                key: const Key('profile-full-name-field'),
                controller: _nameController,
                enabled: !_submitting,
                textInputAction: TextInputAction.next,
                maxLength: 100,
                decoration: const InputDecoration(
                  labelText: 'الاسم الكامل',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
                validator: (value) => _validateRequired(
                  value,
                  'الاسم',
                  min: 2,
                  max: 100,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const Key('profile-governorate-field'),
                initialValue: _governorate,
                decoration: const InputDecoration(
                  labelText: 'المحافظة',
                  prefixIcon: Icon(Icons.map_outlined),
                  border: OutlineInputBorder(),
                ),
                items: governorates
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(value),
                      ),
                    )
                    .toList(),
                onChanged: _submitting
                    ? null
                    : (value) {
                        if (value != null && value != _governorate) {
                          setState(() {
                            _governorate = value;
                            _cityController.clear();
                          });
                        }
                      },
              ),
              const SizedBox(height: 20),
              TextFormField(
                key: const Key('profile-city-field'),
                controller: _cityController,
                enabled: !_submitting,
                textInputAction: TextInputAction.done,
                maxLength: 120,
                onFieldSubmitted: (_) => _save(),
                decoration: InputDecoration(
                  labelText: 'المدينة أو المديرية',
                  prefixIcon: const Icon(Icons.location_city_outlined),
                  border: const OutlineInputBorder(),
                  helperText: 'أدخل المدينة أو المديرية داخل $_governorate',
                ),
                validator: (value) => _validateRequired(
                  value,
                  'المدينة',
                  min: 2,
                  max: 120,
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 4),
                Text(
                  _errorMessage!,
                  key: const Key('profile-update-error'),
                  style: const TextStyle(color: AppTheme.error),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('profile-save-button'),
                onPressed: _submitting ? null : _save,
                icon: _submitting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: const Text('حفظ التعديلات'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
