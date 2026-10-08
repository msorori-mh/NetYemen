// lib/features/admin/presentation/admin_card_vault_ingest_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/error/error_log.dart';
import '../../../core/utils/uuid_generator.dart';
import '../../packages/presentation/package_providers.dart';
import 'admin_providers.dart';

class AdminCardVaultIngestScreen extends ConsumerStatefulWidget {
  const AdminCardVaultIngestScreen({super.key});

  @override
  ConsumerState<AdminCardVaultIngestScreen> createState() =>
      _AdminCardVaultIngestScreenState();
}

class _AdminCardVaultIngestScreenState
    extends ConsumerState<AdminCardVaultIngestScreen> {
  String? _selectedNetworkId;
  String? _selectedPackageId;
  final _cardsController = TextEditingController();
  bool _submitting = false;
  String? _message;
  String? _result;

  /// Idempotency key of the batch being submitted. It is kept across a failed
  /// or ambiguous attempt of the same payload, so retrying can never insert
  /// the same cards twice, and renewed once the payload changes or succeeds.
  String? _batchKey;
  String? _batchFingerprint;

  @override
  void dispose() {
    _cardsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedNetworkId == null || _selectedPackageId == null) {
      setState(() => _message = 'اختر الشبكة والباقة');
      return;
    }

    final cardsText = _cardsController.text.trim();
    List<Map<String, dynamic>> cards;
    try {
      final parsed = jsonDecode(cardsText);
      if (parsed is! List) throw const FormatException('JSON array expected');
      cards = [
        for (final entry in parsed)
          Map<String, dynamic>.from(entry as Map<dynamic, dynamic>),
      ];
    } catch (error, stackTrace) {
      logError('Card batch JSON could not be parsed', error, stackTrace);
      setState(
        () => _message =
            'صيغة JSON غير صحيحة. المطلوب مصفوفة من عناصر الكروت، مثل القالب.',
      );
      return;
    }

    if (cards.isEmpty) {
      setState(() => _message = 'أدخل بطاقة واحدة على الأقل');
      return;
    }

    setState(() {
      _submitting = true;
      _message = null;
      _result = null;
    });

    final fingerprint = '$_selectedNetworkId|$_selectedPackageId|$cardsText';
    if (_batchKey == null || _batchFingerprint != fingerprint) {
      _batchKey = UuidGenerator.generateV4();
      _batchFingerprint = fingerprint;
    }

    try {
      final repo = ref.read(adminRepositoryProvider);
      final result = await repo.ingestCardVaultBatch(
        networkId: _selectedNetworkId!,
        packageId: _selectedPackageId!,
        cards: cards,
        batchKey: _batchKey,
      );
      _batchKey = null;
      _batchFingerprint = null;
      if (mounted) {
        setState(() {
          _result = _describeResult(result);
          _cardsController.clear();
        });
      }
    } catch (error, stackTrace) {
      logError('Card batch ingest failed', error, stackTrace);
      if (mounted) {
        setState(() => _message = _ingestErrorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  String _describeResult(Map<String, dynamic> result) {
    final lines = <String>[
      'تم استيراد ${result['ingested_count'] ?? 0} بطاقة',
    ];
    final duplicates = (result['duplicates_skipped'] as num?)?.toInt() ?? 0;
    if (duplicates > 0) {
      lines.add('تم تجاوز $duplicates بطاقة مكررة موجودة مسبقاً');
    }
    if (result['replayed'] == true) {
      lines.add('هذه الدفعة أُرسلت من قبل؛ عُرضت نتيجتها السابقة دون تكرار.');
    }
    lines.add('معرف الدفعة: ${result['batch_id'] ?? '-'}');
    return lines.join('\n');
  }

  String _ingestErrorMessage(Object error) {
    final message = error.toString();
    if (message.contains('TOO_MANY_CARDS')) {
      return 'عدد الكروت في الدفعة أكبر من المسموح (5000). قسّم الدفعة ثم أعد المحاولة.';
    }
    if (message.contains('INVALID_CARD')) {
      return 'توجد بطاقة غير صالحة في الدفعة (رمز فارغ، أطول من 64 حرفاً، أو يحتوي مسافات). صحّح البيانات ثم أعد المحاولة.';
    }
    if (message.contains('UNAUTHENTICATED') || message.contains('FORBIDDEN')) {
      return 'لا تملك صلاحية استيراد الكروت أو انتهت الجلسة. سجّل الدخول من جديد.';
    }
    return 'تعذر استيراد الدفعة. تحقق من الاتصال ثم أعد المحاولة؛ لن تتكرر البطاقات.';
  }

  @override
  Widget build(BuildContext context) {
    final networksAsync = ref.watch(ownedNetworksProvider);
    final packagesAsync = ref.watch(
      _selectedNetworkId != null
          ? networkPackagesProvider(_selectedNetworkId!)
          : networkPackagesProvider(''),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('استيراد دفعة كروت')),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            networksAsync.when(
              data: (networks) => DropdownButtonFormField<String>(
                initialValue: _selectedNetworkId,
                decoration: const InputDecoration(
                  labelText: 'الشبكة',
                  border: OutlineInputBorder(),
                ),
                hint: const Text('اختر الشبكة'),
                items: networks.map((network) {
                  return DropdownMenuItem(
                    value: network.id,
                    child: Text(network.commercialName),
                  );
                }).toList(),
                onChanged: (value) => setState(() {
                  _selectedNetworkId = value;
                  _selectedPackageId = null;
                }),
              ),
              loading: () => const CircularProgressIndicator(),
              error: (_, __) => const Text(
                'تعذر تحميل الشبكات. تحقق من الاتصال ثم أعد فتح الصفحة.',
              ),
            ),
            const SizedBox(height: 16),
            if (_selectedNetworkId != null)
              packagesAsync.when(
                data: (packages) => DropdownButtonFormField<String>(
                  initialValue: _selectedPackageId,
                  decoration: const InputDecoration(
                    labelText: 'الباقة',
                    border: OutlineInputBorder(),
                  ),
                  hint: const Text('اختر الباقة'),
                  items: packages.map((package) {
                    return DropdownMenuItem(
                      value: package.id,
                      child: Text(package.name),
                    );
                  }).toList(),
                  onChanged: (value) =>
                      setState(() => _selectedPackageId = value),
                ),
                loading: () => const CircularProgressIndicator(),
                error: (_, __) => const Text(
                  'تعذر تحميل الباقات. تحقق من الاتصال ثم أعد فتح الصفحة.',
                ),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _cardsController,
              decoration: const InputDecoration(
                labelText: 'مصفوفة الكروت المشفرة (JSON)',
                hintText:
                    '[{"ciphertext":"...","nonce":"...","auth_tag":"...","expires_at":"..."}]',
                border: OutlineInputBorder(),
              ),
              maxLines: 10,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                _cardsController.text = jsonEncode([
                  {
                    'ciphertext': 'BASE64_CIPHERTEXT_HERE',
                    'nonce': 'NONCE_HERE',
                    'auth_tag': 'AUTH_TAG_HERE',
                    'expires_at': DateTime.now()
                        .add(const Duration(days: 365))
                        .toIso8601String(),
                  },
                ]);
              },
              icon: const Icon(Icons.paste),
              label: const Text('نسخ قالب JSON'),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: const Icon(Icons.upload_file),
              label: _submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('استيراد الدفعة'),
            ),
            if (_message != null) ...[
              const SizedBox(height: 16),
              Text(_message!, style: const TextStyle(color: Colors.red)),
            ],
            if (_result != null) ...[
              const SizedBox(height: 16),
              Card(
                color: Colors.green.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_result!),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
