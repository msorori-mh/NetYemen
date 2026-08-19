import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/uuid_generator.dart';
import '../domain/entities.dart';
import 'package_providers.dart';

class InventoryAdjustmentScreen extends ConsumerStatefulWidget {
  final NetworkPackage package;

  const InventoryAdjustmentScreen({super.key, required this.package});

  @override
  ConsumerState<InventoryAdjustmentScreen> createState() =>
      _InventoryAdjustmentScreenState();
}

class _InventoryAdjustmentScreenState
    extends ConsumerState<InventoryAdjustmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _reasonController = TextEditingController();
  bool _isLoading = false;

  /// Idempotency state for this logical adjustment. The key is bound to the
  /// payload fingerprint so retries of the same adjustment reuse the UUID,
  /// while any material change mints a fresh key.
  String? _pendingIdempotencyKey;
  String? _pendingPayloadFingerprint;

  @override
  void dispose() {
    _quantityController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  String _computeFingerprint(int quantity, String reason) {
    return '${widget.package.id}|$quantity|$reason';
  }

  String _obtainIdempotencyKey(int quantity, String reason) {
    final fingerprint = _computeFingerprint(quantity, reason);
    if (_pendingIdempotencyKey != null &&
        _pendingPayloadFingerprint == fingerprint) {
      return _pendingIdempotencyKey!;
    }
    _pendingPayloadFingerprint = fingerprint;
    _pendingIdempotencyKey = UuidGenerator.generateV4();
    return _pendingIdempotencyKey!;
  }

  @override
  Widget build(BuildContext context) {
    final balanceAsync = ref.watch(packageBalanceProvider(widget.package.id));

    return Scaffold(
      appBar: AppBar(title: const Text('تعديل المخزون')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _BalanceCard(package: widget.package, balanceAsync: balanceAsync),
            const SizedBox(height: 16),
            TextFormField(
              controller: _quantityController,
              decoration: const InputDecoration(
                labelText: 'الكمية',
                hintText: 'أدخل عدد الوحدات (سالب للخصم)',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(signed: true),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'الكمية مطلوبة';
                }
                final parsed = int.tryParse(value);
                if (parsed == null || parsed == 0) {
                  return 'أدخل قيمة صحيحة غير صفرية';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _reasonController,
              decoration: const InputDecoration(
                labelText: 'سبب التعديل',
                hintText: 'مثال: إضافة دفعة جديدة أو تسوية',
                border: OutlineInputBorder(),
              ),
              textDirection: TextDirection.rtl,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'السبب مطلوب';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isLoading ? null : _submit,
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('تطبيق التعديل'),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _isLoading
                  ? null
                  : () => _quickAdjust(-1, 'تصحيح بسيط'),
              child: const Text('خصم وحدة واحدة (تصحيح)'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    await _apply(
      int.parse(_quantityController.text.trim()),
      _reasonController.text.trim(),
    );
  }

  Future<void> _quickAdjust(int quantity, String reason) async {
    _quantityController.text = quantity.toString();
    _reasonController.text = reason;
    await _apply(quantity, reason);
  }

  Future<void> _apply(int quantity, String reason) async {
    setState(() => _isLoading = true);

    final idempotencyKey = _obtainIdempotencyKey(quantity, reason);

    try {
      final repo = ref.read(packageRepositoryProvider);
      await repo.adjustInventory(
        widget.package.id,
        quantity,
        reason,
        idempotencyKey: idempotencyKey,
      );

      _pendingIdempotencyKey = null;
      _pendingPayloadFingerprint = null;

      ref.invalidate(packageBalanceProvider(widget.package.id));
      ref.invalidate(networkMovementsProvider(widget.package.networkId));

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم تعديل المخزون')));
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
}

class _BalanceCard extends StatelessWidget {
  final NetworkPackage package;
  final AsyncValue<PackageInventoryBalance?> balanceAsync;

  const _BalanceCard({required this.package, required this.balanceAsync});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              package.name,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            balanceAsync.when(
              data: (balance) {
                if (balance == null) {
                  return const Text('لا توجد بيانات مخزون');
                }
                return Column(
                  children: [
                    _BalanceRow(
                      label: 'إجمالي الوحدات',
                      value: balance.totalUnits.toString(),
                    ),
                    _BalanceRow(
                      label: 'المتوفر للبيع',
                      value: balance.availableUnits.toString(),
                      valueColor: balance.isOutOfStock
                          ? AppTheme.error
                          : AppTheme.accent,
                    ),
                    if (balance.isOutOfStock)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'المخزون نفد',
                          style: TextStyle(
                            color: AppTheme.error,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Text('خطأ في تحميل المخزون: $error'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BalanceRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _BalanceRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppTheme.textSecondary)),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}
