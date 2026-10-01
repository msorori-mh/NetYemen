import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/owner_providers.dart';
import '../utils/app_theme.dart';
import '../utils/constants.dart';

class CreateFirstNetworkScreen extends ConsumerStatefulWidget {
  const CreateFirstNetworkScreen({super.key});

  @override
  ConsumerState<CreateFirstNetworkScreen> createState() =>
      _CreateFirstNetworkScreenState();
}

class _CreateFirstNetworkScreenState extends ConsumerState<CreateFirstNetworkScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  final _commercialNameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _cityController = TextEditingController();
  final _districtController = TextEditingController();

  String? _selectedGovernorate;

  @override
  void dispose() {
    _commercialNameController.dispose();
    _descriptionController.dispose();
    _cityController.dispose();
    _districtController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedGovernorate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء اختيار المحافظة')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final service = ref.read(ownerServiceProvider);
      await service.createNetworkDraft(
        commercialName: _commercialNameController.text.trim(),
        governorate: _selectedGovernorate!,
        description: _descriptionController.text.trim(),
        city: _cityController.text.trim(),
        district: _districtController.text.trim(),
      );

      // Invalidate owned networks to refresh the RoleGate and go to Dashboard
      ref.invalidate(ownedNetworksProvider);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ في قاعدة البيانات: ${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('حدث خطأ غير متوقع: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _signOut() {
    ref.read(ownerServiceProvider).signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('إنشاء شبكتك الأولى'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _signOut,
            tooltip: 'تسجيل الخروج',
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.storefront_outlined,
                  size: 64,
                  color: AppTheme.primary,
                ),
                const SizedBox(height: 16),
                const Text(
                  'أهلاً بك كصاحب شبكة!',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'يرجى ملء بيانات شبكتك للبدء. بعد الإرسال، سيتم مراجعة الطلب '
                  'من قبل فريق واصل نت واعتماده لتتمكن من إضافة باقات وكروت.',
                  style: TextStyle(color: AppTheme.textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                
                // Commercial Name
                TextFormField(
                  controller: _commercialNameController,
                  decoration: const InputDecoration(
                    labelText: 'الاسم التجاري للشبكة *',
                    prefixIcon: Icon(Icons.business),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'هذا الحقل مطلوب';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                
                // Governorate
                DropdownButtonFormField<String>(
                  initialValue: _selectedGovernorate,
                  decoration: const InputDecoration(
                    labelText: 'المحافظة *',
                    prefixIcon: Icon(Icons.map),
                  ),
                  items: AppConstants.yemenGovernorates
                      .map((gov) => DropdownMenuItem(
                            value: gov,
                            child: Text(gov),
                          ))
                      .toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedGovernorate = val;
                    });
                  },
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'هذا الحقل مطلوب';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                
                // City
                TextFormField(
                  controller: _cityController,
                  decoration: const InputDecoration(
                    labelText: 'المدينة (اختياري)',
                    prefixIcon: Icon(Icons.location_city),
                  ),
                ),
                const SizedBox(height: 16),
                
                // District
                TextFormField(
                  controller: _districtController,
                  decoration: const InputDecoration(
                    labelText: 'المديرية / المنطقة (اختياري)',
                    prefixIcon: Icon(Icons.home_work),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Description
                TextFormField(
                  controller: _descriptionController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'وصف مختصر (اختياري)',
                    prefixIcon: Icon(Icons.description),
                  ),
                ),
                const SizedBox(height: 32),
                
                // Submit Button
                SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('إرسال طلب إنشاء الشبكة'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
