import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/networks_providers.dart';

class PackageFormScreen extends ConsumerStatefulWidget {
  final String networkId;
  final Map<String, dynamic>? packageData;

  const PackageFormScreen({super.key, required this.networkId, this.packageData});

  @override
  ConsumerState<PackageFormScreen> createState() => _PackageFormScreenState();
}

class _PackageFormScreenState extends ConsumerState<PackageFormScreen> {
  final _formKey = GlobalKey<FormState>();
  
  late TextEditingController _nameCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _priceCtrl;
  late TextEditingController _durationValCtrl;
  late TextEditingController _speedCtrl;

  String _currency = 'YER';
  String _packageType = 'time';
  String _durationUnit = 'hour';

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final p = widget.packageData;
    _nameCtrl = TextEditingController(text: p?['name'] ?? '');
    _descCtrl = TextEditingController(text: p?['description'] ?? '');
    _priceCtrl = TextEditingController(text: p?['price']?.toString() ?? '');
    _durationValCtrl = TextEditingController(text: p?['duration_value']?.toString() ?? '');
    _speedCtrl = TextEditingController(text: p?['speed_mbps']?.toString() ?? '');

    if (p != null) {
      _currency = p['currency'] ?? 'YER';
      _packageType = p['package_type'] ?? 'time';
      _durationUnit = p['duration_unit'] ?? 'hour';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _durationValCtrl.dispose();
    _speedCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isLoading = true);
    
    try {
      final name = _nameCtrl.text.trim();
      final desc = _descCtrl.text.trim();
      final price = int.parse(_priceCtrl.text.trim());
      final durVal = _durationValCtrl.text.trim().isNotEmpty ? int.parse(_durationValCtrl.text.trim()) : null;
      final speed = _speedCtrl.text.trim().isNotEmpty ? int.parse(_speedCtrl.text.trim()) : null;

      if (widget.packageData == null) {
        await ref.read(networksServiceProvider).createNetworkPackage(
          networkId: widget.networkId,
          name: name,
          description: desc.isNotEmpty ? desc : null,
          price: price,
          currency: _currency,
          durationValue: durVal,
          durationUnit: _durationUnit,
          speedMbps: speed,
          packageType: _packageType,
        );
      } else {
        await ref.read(networksServiceProvider).updateNetworkPackage(
          packageId: widget.packageData!['id'],
          name: name,
          description: desc.isNotEmpty ? desc : null,
          price: price,
          currency: _currency,
          durationValue: durVal,
          durationUnit: _durationUnit,
          speedMbps: speed,
          packageType: _packageType,
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.packageData != null;
    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'تعديل الباقة' : 'باقة جديدة')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'الاسم'),
              validator: (v) => v == null || v.isEmpty ? 'مطلوب' : null,
            ),
            TextFormField(
              controller: _descCtrl,
              decoration: const InputDecoration(labelText: 'الوصف (اختياري)'),
            ),
            TextFormField(
              controller: _priceCtrl,
              decoration: const InputDecoration(labelText: 'السعر'),
              keyboardType: TextInputType.number,
              validator: (v) => v == null || v.isEmpty ? 'مطلوب' : null,
            ),
            DropdownButtonFormField<String>(
              initialValue: _packageType,
              decoration: const InputDecoration(labelText: 'نوع الباقة'),
              items: const [
                DropdownMenuItem(value: 'time', child: Text('وقت (Time)')),
                DropdownMenuItem(value: 'volume', child: Text('حجم (Volume)')),
                DropdownMenuItem(value: 'unlimited', child: Text('غير محدود (Unlimited)')),
              ],
              onChanged: (v) => setState(() => _packageType = v!),
            ),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _durationValCtrl,
                    decoration: const InputDecoration(labelText: 'المدة (اختياري)'),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _durationUnit,
                    decoration: const InputDecoration(labelText: 'الوحدة'),
                    items: const [
                      DropdownMenuItem(value: 'hour', child: Text('ساعة')),
                      DropdownMenuItem(value: 'day', child: Text('يوم')),
                      DropdownMenuItem(value: 'week', child: Text('أسبوع')),
                      DropdownMenuItem(value: 'month', child: Text('شهر')),
                    ],
                    onChanged: (v) => setState(() => _durationUnit = v!),
                  ),
                ),
              ],
            ),
            TextFormField(
              controller: _speedCtrl,
              decoration: const InputDecoration(labelText: 'السرعة Mbps (اختياري)'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 24),
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ElevatedButton(
                    onPressed: _submit,
                    child: Text(isEdit ? 'حفظ' : 'إنشاء'),
                  ),
          ],
        ),
      ),
    );
  }
}
