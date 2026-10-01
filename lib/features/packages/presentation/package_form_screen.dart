import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/entities.dart';
import 'package_providers.dart';

class PackageFormScreen extends ConsumerStatefulWidget {
  final String networkId;
  final NetworkPackage? package;

  const PackageFormScreen({super.key, required this.networkId, this.package});

  @override
  ConsumerState<PackageFormScreen> createState() => _PackageFormScreenState();
}

class _PackageFormScreenState extends ConsumerState<PackageFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _priceController;
  late final TextEditingController _durationValueController;
  late final TextEditingController _speedController;
  String _durationUnit = 'day';
  String _packageType = 'time';
  bool _isLoading = false;

  bool get _isEditing => widget.package != null;

  @override
  void initState() {
    super.initState();
    final package = widget.package;
    _nameController = TextEditingController(text: package?.name ?? '');
    _descriptionController = TextEditingController(
      text: package?.description ?? '',
    );
    _priceController = TextEditingController(
      text: package == null ? '' : (package.price / 100).toString(),
    );
    _durationValueController = TextEditingController(
      text: package?.durationValue?.toString() ?? '',
    );
    _speedController = TextEditingController(
      text: package?.speedMbps?.toString() ?? '',
    );
    if (package != null) {
      _durationUnit = package.durationUnit ?? 'day';
      _packageType = package.packageType;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _durationValueController.dispose();
    _speedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'تعديل الباقة' : 'باقة جديدة')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'اسم الباقة',
                hintText: 'مثال: باقة يومية',
                border: OutlineInputBorder(),
              ),
              textDirection: TextDirection.rtl,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'اسم الباقة مطلوب';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'الوصف',
                hintText: 'وصف مختصر للباقة',
                border: OutlineInputBorder(),
              ),
              textDirection: TextDirection.rtl,
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _priceController,
              decoration: const InputDecoration(
                labelText: 'السعر (YER)',
                hintText: 'مثال: 1000',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'السعر مطلوب';
                }
                final parsed = double.tryParse(value);
                if (parsed == null || parsed < 0) {
                  return 'أدخل سعراً صحيحاً';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _durationValueController,
                    decoration: const InputDecoration(
                      labelText: 'المدة',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value != null && value.isNotEmpty) {
                        final parsed = int.tryParse(value);
                        if (parsed == null || parsed <= 0) {
                          return 'أدخل قيمة صحيحة';
                        }
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<String>(
                    initialValue: _durationUnit,
                    decoration: const InputDecoration(
                      labelText: 'وحدة المدة',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'hour', child: Text('ساعة')),
                      DropdownMenuItem(value: 'day', child: Text('يوم')),
                      DropdownMenuItem(value: 'week', child: Text('أسبوع')),
                      DropdownMenuItem(value: 'month', child: Text('شهر')),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _durationUnit = value);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _speedController,
              decoration: const InputDecoration(
                labelText: 'السرعة (Mbps)',
                hintText: 'اختياري',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value != null && value.isNotEmpty) {
                  final parsed = int.tryParse(value);
                  if (parsed == null || parsed < 0) {
                    return 'أدخل سرعة صحيحة';
                  }
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _packageType,
              decoration: const InputDecoration(
                labelText: 'نوع الباقة',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'time', child: Text('زمنية')),
                DropdownMenuItem(value: 'volume', child: Text('حجمية')),
                DropdownMenuItem(value: 'unlimited', child: Text('غير محدود')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _packageType = value);
              },
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isLoading ? null : _save,
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_isEditing ? 'حفظ التغييرات' : 'إنشاء الباقة'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final repo = ref.read(packageRepositoryProvider);
      final price = (_parseDouble(_priceController.text) * 100).round();
      final durationValue = _durationValueController.text.isEmpty
          ? null
          : int.parse(_durationValueController.text);
      final speedMbps = _speedController.text.isEmpty
          ? null
          : int.parse(_speedController.text);

      if (_isEditing) {
        await repo.updatePackage(
          widget.package!.id,
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim(),
          price: price,
          durationValue: durationValue,
          durationUnit: _durationUnit,
          speedMbps: speedMbps,
          packageType: _packageType,
        );
      } else {
        await repo.createPackage(
          networkId: widget.networkId,
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim(),
          price: price,
          durationValue: durationValue,
          durationUnit: _durationUnit,
          speedMbps: speedMbps,
          packageType: _packageType,
        );
      }

      ref.invalidate(networkPackagesProvider(widget.networkId));

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing ? 'تم تحديث الباقة' : 'تم إنشاء الباقة'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('خطأ: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  double _parseDouble(String value) {
    final normalized = value.trim().replaceAll(',', '');
    return double.parse(normalized);
  }
}
