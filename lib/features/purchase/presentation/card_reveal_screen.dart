// lib/features/purchase/presentation/card_reveal_screen.dart

import 'dart:async';

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
  bool _disputeSubmitted = false;
  final _reasonController = TextEditingController();
  Timer? _clipboardClearTimer;
  String? _message;

  @override
  void dispose() {
    _clipboardClearTimer?.cancel();
    _reasonController.dispose();
    super.dispose();
  }

  bool get _disputeEligible {
    final deadline = widget.revealedInfo.disputeDeadline;
    if (deadline == null || _disputeSubmitted) return false;
    return DateTime.now().isBefore(deadline);
  }

  String get _remainingText {
    final deadline = widget.revealedInfo.disputeDeadline;
    if (_disputeSubmitted) return 'تم تسجيل بلاغ الكرت غير الصالح.';
    if (deadline == null) return 'تعذر التحقق من مهلة النزاع.';
    final remaining = deadline.difference(DateTime.now());
    if (remaining.isNegative) return 'انتهت مهلة فتح النزاع';
    final minutes = (remaining.inSeconds + 59) ~/ 60;
    return 'متبقي لفتح نزاع: $minutes دقيقة';
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
                            key: const Key('card-secret-visibility'),
                            tooltip: _showSecret ? 'إخفاء الكرت' : 'إظهار الكرت',
                            onPressed: () =>
                                setState(() => _showSecret = !_showSecret),
                            icon: Icon(
                              _showSecret
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                          ),
                          IconButton(
                            key: const Key('card-secret-copy'),
                            tooltip: 'نسخ الكرت',
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
    _clipboardClearTimer?.cancel();
    _clipboardClearTimer = Timer(const Duration(seconds: 60), () async {
      final current = await Clipboard.getData(Clipboard.kTextPlain);
      if (current?.text == text) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
    });
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        const SnackBar(
          content: Text('تم النسخ — سيُمسح من الحافظة بعد دقيقة'),
        ),
      );
    }
  }

  Future<void> _submitDispute() async {
    if (!_disputeEligible) {
      setState(() => _message = 'انتهت أو تعذر التحقق من مهلة فتح النزاع.');
      return;
    }
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
        setState(() {
          _disputeSubmitted = true;
          _message = 'تم فتح النزاع بنجاح';
        });
        _reasonController.clear();
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'تعذر تأكيد فتح النزاع. تحقق من الاتصال ثم راجع مشترياتك قبل إعادة المحاولة.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _disputing = false);
      }
    }
  }
}
