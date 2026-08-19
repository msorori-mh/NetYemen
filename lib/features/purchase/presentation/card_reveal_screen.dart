// lib/features/purchase/presentation/card_reveal_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/entities.dart';
import 'purchase_providers.dart';

class CardRevealScreen extends ConsumerStatefulWidget {
  final RevealedCardInfo revealedInfo;

  const CardRevealScreen({super.key, required this.revealedInfo});

  @override
  ConsumerState<CardRevealScreen> createState() => _CardRevealScreenState();
}

class _CardRevealScreenState extends ConsumerState<CardRevealScreen> {
  bool _showSecret = false;
  bool _disputing = false;
  final _reasonController = TextEditingController();
  String? _message;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  bool get _disputeEligible {
    final deadline = widget.revealedInfo.disputeDeadline;
    if (deadline == null) return true;
    return DateTime.now().isBefore(deadline);
  }

  String get _remainingText {
    final deadline = widget.revealedInfo.disputeDeadline;
    if (deadline == null) return '';
    final remaining = deadline.difference(DateTime.now());
    if (remaining.isNegative) return 'انتهت مهلة فتح النزاع';
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds % 60;
    return 'متبقي لفتح نزاع: $minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('كرتك')),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: ListView(
            children: [
              Card(
                color: Colors.amber.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'تنبيه مهم',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.deepOrange,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'يمكنك فتح نزاع "الكرت غير صالح" خلال 30 دقيقة من لحظة الكشف فقط. بعد انتهاء المهلة يجب فتح تذكرة دعم عادية.',
                        style: TextStyle(color: Colors.grey.shade800),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'رقم الكرت / البيانات',
                        style: TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _showSecret
                                  ? widget.revealedInfo.plaintext
                                  : '••••••••••••',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 2,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () =>
                                setState(() => _showSecret = !_showSecret),
                            icon: Icon(
                              _showSecret
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                          ),
                          IconButton(
                            onPressed: () =>
                                _copyToClipboard(widget.revealedInfo.plaintext),
                            icon: const Icon(Icons.copy),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _remainingText,
                style: TextStyle(
                  color: _disputeEligible ? Colors.orange : Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 24),
              if (_disputeEligible) ...[
                TextField(
                  controller: _reasonController,
                  decoration: const InputDecoration(
                    labelText: 'سبب النزاع',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _disputing ? null : _submitDispute,
                  icon: const Icon(Icons.report_problem),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  label: _disputing
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('الكرت غير صالح - فتح نزاع'),
                ),
              ],
              if (_message != null) ...[
                const SizedBox(height: 16),
                Text(
                  _message!,
                  style: TextStyle(
                    color:
                        _message!.startsWith('تم') ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم النسخ')));
    }
  }

  Future<void> _submitDispute() async {
    final reason = _reasonController.text.trim();
    if (reason.isEmpty) {
      setState(() => _message = 'أدخل سبب النزاع');
      return;
    }

    setState(() {
      _disputing = true;
      _message = null;
    });

    try {
      final repo = ref.read(purchaseRepositoryProvider);
      await repo.submitInvalidCardDispute(
        widget.revealedInfo.purchaseId,
        reason,
      );
      if (mounted) {
        setState(() => _message = 'تم فتح النزاع بنجاح');
        _reasonController.clear();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _message = 'فشل فتح النزاع: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _disputing = false);
      }
    }
  }
}
