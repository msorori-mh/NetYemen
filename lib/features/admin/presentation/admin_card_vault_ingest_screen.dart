// lib/features/admin/presentation/admin_card_vault_ingest_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  final _keyVersionController = TextEditingController(text: 'v1');
  final _cardsController = TextEditingController();
  bool _submitting = false;
  String? _message;
  String? _result;

  @override
  void dispose() {
    _keyVersionController.dispose();
    _cardsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedNetworkId == null || _selectedPackageId == null) {
      setState(() => _message = 'اختر الشبكة والباقة');
      return;
    }

    final keyVersion = _keyVersionController.text.trim();
    if (keyVersion.isEmpty) {
      setState(() => _message = 'أدخل إصدار المفتاح');
      return;
    }

    List<Map<String, dynamic>> cards;
    try {
      final parsed = jsonDecode(_cardsController.text.trim());
      if (parsed is! List) throw const FormatException('JSON array expected');
      cards = parsed.cast<Map<String, dynamic>>();
    } catch (e) {
      setState(() => _message = 'صيغة JSON غير صحيحة: $e');
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

    try {
      final repo = ref.read(adminRepositoryProvider);
      final result = await repo.ingestCardVaultBatch(
        networkId: _selectedNetworkId!,
        packageId: _selectedPackageId!,
        cards: cards,
        keyVersion: keyVersion,
      );
      if (mounted) {
        setState(() {
          _result =
              'تم استيراد ${result['ingested_count']} بطاقة\nمعرف الدفعة: ${result['batch_id']}';
          _cardsController.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _message = 'فشل الاستيراد: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
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
              error: (e, _) => Text('خطأ في الشبكات: $e'),
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
                error: (e, _) => Text('خطأ في الباقات: $e'),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _keyVersionController,
              decoration: const InputDecoration(
                labelText: 'إصدار المفتاح',
                border: OutlineInputBorder(),
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
