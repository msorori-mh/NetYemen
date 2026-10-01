// lib/screens/inventory/card_upload_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/inventory_providers.dart';
import '../../providers/owner_providers.dart';
import '../../services/owner_inventory_service.dart';
import '../../utils/app_theme.dart';

/// F-OWN-04: شاشة رفع دُفعة كروت مع التحقق المسبق.
///
/// يختار صاحب الشبكة الشبكة → الباقة → يلصق أرقام PIN (واحد بكل سطر)
/// → يحدد تاريخ انتهاء اختياري → المعاينة والتحقق → الرفع.
class CardUploadScreen extends ConsumerStatefulWidget {
  const CardUploadScreen({super.key});

  @override
  ConsumerState<CardUploadScreen> createState() => _CardUploadScreenState();
}

class _CardUploadScreenState extends ConsumerState<CardUploadScreen> {
  final _pinsController = TextEditingController();
  String? _selectedNetworkId;
  String? _selectedPackageId;
  DateTime? _expiresAt;
  bool _isUploading = false;

  // نتيجة التحقق المسبق
  Map<String, dynamic>? _validationResult;

  @override
  void dispose() {
    _pinsController.dispose();
    super.dispose();
  }

  void _runValidation() {
    final result = OwnerInventoryService.validateBatch(_pinsController.text);
    setState(() => _validationResult = result);
  }

  Future<void> _pickExpiryDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 90)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (picked != null) {
      setState(() => _expiresAt = picked);
    }
  }

  Future<void> _upload() async {
    if (_selectedNetworkId == null || _selectedPackageId == null) {
      _showSnackBar('اختر الشبكة والباقة أولاً', isError: true);
      return;
    }

    if (_validationResult == null) {
      _runValidation();
    }

    final validPins = (_validationResult?['validPins'] as List<String>?) ?? [];
    if (validPins.isEmpty) {
      _showSnackBar('لا توجد كروت صالحة للرفع', isError: true);
      return;
    }

    setState(() => _isUploading = true);

    try {
      final service = ref.read(inventoryServiceProvider);
      final result = await service.uploadCardBatch(
        networkId: _selectedNetworkId!,
        packageId: _selectedPackageId!,
        pins: validPins,
        expiresAt: _expiresAt?.toIso8601String(),
      );

      if (!mounted) return;
      _showSnackBar(
        'تم رفع ${result['ingested_count']} كرت بنجاح\n'
        'رقم الدفعة: ${result['batch_id']}',
      );
      _pinsController.clear();
      setState(() => _validationResult = null);

      // تحديث المخزون والكروت
      ref.invalidate(inventoryBalancesProvider);
      ref.invalidate(cardStateBreakdownProvider);
      ref.invalidate(cardVaultMetadataProvider);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar(_extractError(e), isError: true);
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppTheme.error : AppTheme.accentDark,
      ),
    );
  }

  String _extractError(Object e) {
    final str = e.toString();
    // أخطاء Supabase RPC تأتي غالباً بنص مثل 'FORBIDDEN_ROLE: ...'
    final idx = str.indexOf(':');
    if (idx > 0 && idx < 40) return str.substring(idx + 1).trim();
    return str;
  }

  @override
  Widget build(BuildContext context) {
    final networksAsync = ref.watch(ownedNetworksProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('رفع دُفعة كروت')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ───── اختيار الشبكة ─────
            networksAsync.when(
              data: (networks) {
                if (networks.isEmpty) {
                  return const Text('لا توجد شبكات مسجَّلة.');
                }
                return DropdownButtonFormField<String>(
                  initialValue: _selectedNetworkId,
                  decoration: const InputDecoration(
                    labelText: 'الشبكة',
                    border: OutlineInputBorder(),
                  ),
                  items: networks.map((n) {
                    return DropdownMenuItem(value: n.id, child: Text(n.commercialName));
                  }).toList(),
                  onChanged: (v) => setState(() {
                    _selectedNetworkId = v;
                    _selectedPackageId = null; // إعادة تعيين الباقة
                  }),
                );
              },
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => const Text('تعذّر تحميل الشبكات'),
            ),

            const SizedBox(height: 12),

            // ───── اختيار الباقة ─────
            if (_selectedNetworkId != null) ...[
              ref.watch(networkPackagesProvider(_selectedNetworkId!)).when(
                data: (packages) {
                  if (packages.isEmpty) {
                    return const Text('لا توجد باقات لهذه الشبكة.');
                  }
                  return DropdownButtonFormField<String>(
                    initialValue: _selectedPackageId,
                    decoration: const InputDecoration(
                      labelText: 'الباقة',
                      border: OutlineInputBorder(),
                    ),
                    items: packages.map((p) {
                      final name = p['name'] ?? 'باقة';
                      final price = p['price'] ?? '—';
                      return DropdownMenuItem(
                        value: p['id'] as String,
                        child: Text('$name ($price ر.ي)'),
                      );
                    }).toList(),
                    onChanged: (v) => setState(() => _selectedPackageId = v),
                  );
                },
                loading: () => const LinearProgressIndicator(),
                error: (_, __) => const Text('تعذّر تحميل الباقات'),
              ),
              const SizedBox(height: 12),
            ],

            // ───── حقل لصق الأرقام ─────
            TextField(
              controller: _pinsController,
              maxLines: 8,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(
                labelText: 'أرقام الكروت (PIN) — واحد بكل سطر',
                hintText: '12345678\n87654321\n...',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 12),

            // ───── تاريخ الانتهاء ─────
            OutlinedButton.icon(
              onPressed: _pickExpiryDate,
              icon: const Icon(Icons.calendar_today, size: 18),
              label: Text(
                _expiresAt != null
                    ? 'ينتهي: ${_expiresAt!.toIso8601String().substring(0, 10)}'
                    : 'تاريخ الانتهاء (اختياري)',
              ),
            ),

            const SizedBox(height: 16),

            // ───── زر المعاينة والتحقق ─────
            ElevatedButton.icon(
              onPressed: _runValidation,
              icon: const Icon(Icons.checklist, size: 18),
              label: const Text('معاينة وتحقق'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.info,
                foregroundColor: AppTheme.textOnPrimary,
              ),
            ),

            // ───── نتيجة التحقق ─────
            if (_validationResult != null) ...[
              const SizedBox(height: 16),
              _ValidationSummary(result: _validationResult!),
            ],

            const SizedBox(height: 16),

            // ───── زر الرفع ─────
            ElevatedButton.icon(
              onPressed: _isUploading ? null : _upload,
              icon: _isUploading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.upload_file, size: 18),
              label: Text(_isUploading ? 'جارٍ الرفع…' : 'رفع الكروت'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: AppTheme.textOnPrimary,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ملخّص نتيجة التحقق المسبق.
class _ValidationSummary extends StatelessWidget {
  final Map<String, dynamic> result;

  const _ValidationSummary({required this.result});

  @override
  Widget build(BuildContext context) {
    final validPins = (result['validPins'] as List?)?.length ?? 0;
    final duplicates = result['duplicates'] as List? ?? [];
    final emptyLines = result['emptyLines'] as int? ?? 0;

    return Card(
      color: duplicates.isNotEmpty
          ? AppTheme.warning.withValues(alpha: 0.08)
          : AppTheme.accent.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ملخّص المعاينة',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: duplicates.isNotEmpty ? AppTheme.warning : AppTheme.accentDark,
              ),
            ),
            const SizedBox(height: 8),
            _row(Icons.check_circle_outline, 'كروت صالحة', '$validPins', AppTheme.accentDark),
            if (duplicates.isNotEmpty)
              _row(Icons.warning_amber_rounded, 'مكررة (ستُرفض)', '${duplicates.length}', AppTheme.warning),
            if (emptyLines > 0)
              _row(Icons.remove_circle_outline, 'أسطر فارغة', '$emptyLines', AppTheme.textMuted),
            if (duplicates.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'المكررة: ${duplicates.join(', ')}',
                style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(IconData icon, String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 14)),
          const Spacer(),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}
