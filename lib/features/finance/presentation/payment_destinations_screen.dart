// lib/features/finance/presentation/payment_destinations_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import 'finance_providers.dart';

class PaymentDestinationsScreen extends ConsumerWidget {
  const PaymentDestinationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final destinationsAsync = ref.watch(paymentDestinationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('وجهات الدفع'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(paymentDestinationsProvider),
          ),
        ],
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: destinationsAsync.when(
          data: (destinations) => _DestinationList(destinations: destinations),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const Center(
            child: Text('تعذر تحميل وجهات الدفع. حاول مرة أخرى.'),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _openEditor(
    BuildContext context,
    WidgetRef ref, {
    Map<String, dynamic>? destination,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _DestinationEditor(
        destination: destination,
        onSaved: () => ref.invalidate(paymentDestinationsProvider),
      ),
    );
  }
}

class _DestinationList extends ConsumerWidget {
  final List<Map<String, dynamic>> destinations;

  const _DestinationList({required this.destinations});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (destinations.isEmpty) {
      return const Center(child: Text('لا توجد وجهات دفع'));
    }

    final sorted = List<Map<String, dynamic>>.from(destinations)
      ..sort(
        (a, b) => (a['sort_order'] as int? ?? 0).compareTo(
          b['sort_order'] as int? ?? 0,
        ),
      );

    return ListView(
      children: sorted.asMap().entries.map((entry) {
        final index = entry.key;
        final d = entry.value;
        final isActive = d['is_active'] as bool? ?? true;
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: ListTile(
            leading: Icon(
              _providerIcon(d['provider_type'] as String? ?? 'other'),
              color: isActive ? AppTheme.primary : AppTheme.textSecondary,
            ),
            title: Text(d['display_name'] as String? ?? 'وجهة'),
            subtitle: Text(
              '${d['account_holder_name'] ?? '-'}\n'
              '${d['account_identifier'] ?? '-'}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_upward),
                  onPressed: index == 0
                      ? null
                      : () => _move(context, ref, sorted, index, index - 1),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_downward),
                  onPressed: index == sorted.length - 1
                      ? null
                      : () => _move(context, ref, sorted, index, index + 1),
                ),
                Switch(
                  value: isActive,
                  onChanged: (value) =>
                      _toggleActive(context, ref, d['id'] as String, value),
                ),
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () => _openEditor(context, ref, destination: d),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  IconData _providerIcon(String type) {
    switch (type) {
      case 'bank_account':
        return Icons.account_balance;
      case 'mobile_wallet':
        return Icons.phone_android;
      case 'manual_transfer':
        return Icons.transfer_within_a_station;
      default:
        return Icons.payment;
    }
  }

  Future<void> _move(
    BuildContext context,
    WidgetRef ref,
    List<Map<String, dynamic>> sorted,
    int fromIndex,
    int toIndex,
  ) async {
    final reordered = List<Map<String, dynamic>>.from(sorted);
    final item = reordered.removeAt(fromIndex);
    reordered.insert(toIndex, item);
    final orderedIds = reordered.map((d) => d['id'] as String).toList();
    try {
      final repo = ref.read(financeRepositoryProvider);
      await repo.reorderPaymentDestinations(orderedIds);
      ref.invalidate(paymentDestinationsProvider);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر إعادة ترتيب وجهات الدفع. حاول مرة أخرى.'),
          ),
        );
      }
    }
  }

  Future<void> _toggleActive(
    BuildContext context,
    WidgetRef ref,
    String id,
    bool active,
  ) async {
    if (!active) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('تعطيل وجهة الدفع'),
          content: const Text(
            'لن تظهر هذه الوجهة للعملاء بعد التعطيل. هل تريد المتابعة؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('تعطيل'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
    }

    try {
      final repo = ref.read(financeRepositoryProvider);
      await repo.setPaymentDestinationActive(id, active);
      ref.invalidate(paymentDestinationsProvider);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر تحديث وجهة الدفع. حاول مرة أخرى.'),
          ),
        );
      }
    }
  }

  void _openEditor(
    BuildContext context,
    WidgetRef ref, {
    Map<String, dynamic>? destination,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _DestinationEditor(
        destination: destination,
        onSaved: () => ref.invalidate(paymentDestinationsProvider),
      ),
    );
  }
}

class _DestinationEditor extends ConsumerStatefulWidget {
  final Map<String, dynamic>? destination;
  final VoidCallback onSaved;

  const _DestinationEditor({this.destination, required this.onSaved});

  @override
  ConsumerState<_DestinationEditor> createState() => _DestinationEditorState();
}

class _DestinationEditorState extends ConsumerState<_DestinationEditor> {
  final _displayNameController = TextEditingController();
  final _holderController = TextEditingController();
  final _identifierController = TextEditingController();
  final _instructionsController = TextEditingController();
  final _currencyController = TextEditingController();
  String _providerType = 'bank_account';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final d = widget.destination;
    if (d != null) {
      _displayNameController.text = d['display_name'] as String? ?? '';
      _holderController.text = d['account_holder_name'] as String? ?? '';
      _identifierController.text = d['account_identifier'] as String? ?? '';
      _instructionsController.text = d['instructions'] as String? ?? '';
      _currencyController.text = d['currency'] as String? ?? 'YER';
      _providerType = d['provider_type'] as String? ?? 'bank_account';
    } else {
      _currencyController.text = 'YER';
    }
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _holderController.dispose();
    _identifierController.dispose();
    _instructionsController.dispose();
    _currencyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final displayName = _displayNameController.text.trim();
    if (displayName.isEmpty) return;

    setState(() => _saving = true);

    try {
      final repo = ref.read(financeRepositoryProvider);
      if (widget.destination == null) {
        await repo.createPaymentDestination(
          providerType: _providerType,
          displayName: displayName,
          accountHolderName: _holderController.text.trim().isEmpty
              ? null
              : _holderController.text.trim(),
          accountIdentifier: _identifierController.text.trim().isEmpty
              ? null
              : _identifierController.text.trim(),
          instructions: _instructionsController.text.trim().isEmpty
              ? null
              : _instructionsController.text.trim(),
          currency: _currencyController.text.trim().isEmpty
              ? 'YER'
              : _currencyController.text.trim(),
        );
      } else {
        await repo.updatePaymentDestination(
          widget.destination!['id'] as String,
          providerType: _providerType,
          displayName: displayName,
          accountHolderName: _holderController.text.trim().isEmpty
              ? null
              : _holderController.text.trim(),
          accountIdentifier: _identifierController.text.trim().isEmpty
              ? null
              : _identifierController.text.trim(),
          instructions: _instructionsController.text.trim().isEmpty
              ? null
              : _instructionsController.text.trim(),
          currency: _currencyController.text.trim().isEmpty
              ? null
              : _currencyController.text.trim(),
        );
      }
      widget.onSaved();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('تعذر حفظ وجهة الدفع. تحقق من البيانات وحاول مجدداً.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.destination == null
                    ? 'إضافة وجهة دفع'
                    : 'تعديل وجهة الدفع',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _providerType,
                decoration: const InputDecoration(
                  labelText: 'نوع الوسيط',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'bank_account',
                    child: Text('حساب بنكي'),
                  ),
                  DropdownMenuItem(
                    value: 'mobile_wallet',
                    child: Text('محفظة جوال'),
                  ),
                  DropdownMenuItem(
                    value: 'manual_transfer',
                    child: Text('تحويل يدوي'),
                  ),
                  DropdownMenuItem(value: 'other', child: Text('أخرى')),
                ],
                onChanged: (value) =>
                    setState(() => _providerType = value ?? 'bank_account'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _displayNameController,
                decoration: const InputDecoration(
                  labelText: 'اسم العرض',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _holderController,
                decoration: const InputDecoration(
                  labelText: 'اسم صاحب الحساب',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _identifierController,
                decoration: const InputDecoration(
                  labelText: 'رقم الحساب / المحفظة',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _instructionsController,
                decoration: const InputDecoration(
                  labelText: 'التعليمات',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _currencyController,
                decoration: const InputDecoration(
                  labelText: 'العملة',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const CircularProgressIndicator()
                      : const Text('حفظ'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
