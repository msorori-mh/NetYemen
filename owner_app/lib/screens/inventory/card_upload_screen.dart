// lib/screens/inventory/card_upload_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../providers/inventory_providers.dart';
import '../../providers/networks_providers.dart';
import '../../providers/owner_providers.dart';
import '../../utils/app_theme.dart';
import '../../utils/card_batch_validator.dart';
import '../../utils/error_text.dart';
import '../../widgets/card_batch_summary.dart';

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

  // مفتاح عدم التكرار: يبقى نفسه عند إعادة المحاولة لنفس المحتوى، ويتجدّد
  // عند تغيّر المحتوى أو بعد نجاح مؤكَّد.
  final _batchKeys = CardBatchKeyTracker(() => const Uuid().v4());

  String? _selectedNetworkId;
  String? _selectedPackageId;
  DateTime? _expiresAt;
  bool _isUploading = false;
  String _lastText = '';

  // نتيجة التحقق المسبق — صالحة فقط للنص الحالي (تُمسح عند أي تعديل).
  CardBatchValidation? _validation;

  // نتيجة آخر رفع ناجح كما أعادها الخادم.
  CardBatchUploadResult? _lastResult;

  @override
  void initState() {
    super.initState();
    _pinsController.addListener(_onPinsChanged);
  }

  @override
  void dispose() {
    _pinsController.removeListener(_onPinsChanged);
    _pinsController.dispose();
    super.dispose();
  }

  void _onPinsChanged() {
    final text = _pinsController.text;
    if (text == _lastText) return;
    _lastText = text;
    if (_validation == null && _lastResult == null) return;
    setState(() {
      _validation = null;
      _lastResult = null;
    });
  }

  void _runValidation() {
    final validation = validateCardBatch(_pinsController.text);
    setState(() => _validation = validation);
  }

  Future<void> _pickExpiryDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 90)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (picked != null && mounted) {
      setState(() => _expiresAt = picked);
    }
  }

  String _formatDay(DateTime day) {
    final month = day.month.toString().padLeft(2, '0');
    final dayOfMonth = day.day.toString().padLeft(2, '0');
    return '${day.year}-$month-$dayOfMonth';
  }

  Future<void> _upload() async {
    if (_isUploading) return;
    final networkId = _selectedNetworkId;
    final packageId = _selectedPackageId;
    if (networkId == null || packageId == null) {
      _showSnackBar('اختر الشبكة والباقة أولاً', isError: true);
      return;
    }

    // التحقق دائماً من النص الحالي: لا نرفع أبداً نتيجة معاينة قديمة.
    final validation = validateCardBatch(_pinsController.text);
    setState(() {
      _validation = validation;
      _lastResult = null;
    });

    if (validation.invalidCount > 0) {
      _showSnackBar(
        'صحّح الأسطر غير الصالحة قبل الرفع (راجع ملخّص المعاينة).',
        isError: true,
      );
      return;
    }
    if (validation.exceedsLimit) {
      _showSnackBar(
        'الحد الأقصى للدفعة الواحدة $maxCardBatchSize كرت.',
        isError: true,
      );
      return;
    }
    if (!validation.canUpload) {
      _showSnackBar('لا توجد كروت صالحة للرفع', isError: true);
      return;
    }

    final expiryDay = _expiresAt;
    final expiresAt = expiryDay == null ? null : cardExpiryIsoUtc(expiryDay);
    final batchKey = _batchKeys.keyFor(
      cardBatchSignature(
        networkId: networkId,
        packageId: packageId,
        expiresAt: expiresAt,
        pins: validation.validPins,
      ),
    );

    setState(() => _isUploading = true);

    try {
      final service = ref.read(inventoryServiceProvider);
      final result = await service.uploadCardBatch(
        networkId: networkId,
        packageId: packageId,
        pins: validation.validPins,
        batchKey: batchKey,
        expiresAt: expiresAt,
      );

      // نجاح مؤكَّد: الدفعة التالية تحصل على مفتاح جديد.
      _batchKeys.confirmSuccess();
      if (!mounted) return;

      _pinsController.clear();
      setState(() {
        _validation = null;
        _lastResult = result;
      });
      _showSnackBar(_resultMessage(result));

      // تحديث المخزون والكروت
      ref.invalidate(inventoryBalancesProvider);
      ref.invalidate(cardStateBreakdownProvider);
      ref.invalidate(cardVaultMetadataProvider);
    } catch (e, st) {
      // المفتاح يبقى كما هو: إعادة المحاولة لنفس المحتوى لا تكرّر الكروت.
      final message = describeError(
        e,
        stackTrace: st,
        where: 'owner.card_upload',
      );
      if (!mounted) return;
      _showSnackBar(
        '$message\nيمكنك إعادة المحاولة بأمان؛ لن تُرفع الكروت مرتين.',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  String _resultMessage(CardBatchUploadResult result) {
    final skipped = result.duplicatesSkipped > 0
        ? '\nتم تخطي ${result.duplicatesSkipped} كرت موجود مسبقاً.'
        : '';
    if (result.replayed) {
      return 'هذه الدفعة سبق رفعها (${result.ingestedCount} كرت)؛ '
          'لم تُرفع مرة ثانية.$skipped';
    }
    return 'تم رفع ${result.ingestedCount} كرت بنجاح.$skipped';
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppTheme.error : AppTheme.accentDark,
      ),
    );
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
                    return DropdownMenuItem(
                      value: n.id,
                      child: Text(n.commercialName),
                    );
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
                        // مفتاح مرتبط بالشبكة: تبديل الشبكة يعيد بناء الحقل بدل
                        // أن يحتفظ بباقة لا تتبع الشبكة الجديدة.
                        key: ValueKey(_selectedNetworkId),
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
                        onChanged: (v) =>
                            setState(() => _selectedPackageId = v),
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
              enabled: !_isUploading,
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
                    ? 'ينتهي بنهاية يوم: ${_formatDay(_expiresAt!)}'
                    : 'تاريخ الانتهاء (اختياري)',
              ),
            ),

            const SizedBox(height: 16),

            // ───── زر المعاينة والتحقق ─────
            ElevatedButton.icon(
              onPressed: _isUploading ? null : _runValidation,
              icon: const Icon(Icons.checklist, size: 18),
              label: const Text('معاينة وتحقق'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.info,
                foregroundColor: AppTheme.textOnPrimary,
              ),
            ),

            // ───── نتيجة التحقق ─────
            if (_validation != null) ...[
              const SizedBox(height: 16),
              CardBatchValidationSummary(validation: _validation!),
            ],

            // ───── نتيجة الرفع من الخادم ─────
            if (_lastResult != null) ...[
              const SizedBox(height: 16),
              CardBatchResultCard(result: _lastResult!),
            ],

            const SizedBox(height: 16),

            // ───── زر الرفع ─────
            ElevatedButton.icon(
              onPressed: _isUploading ? null : _upload,
              icon: _isUploading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
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
