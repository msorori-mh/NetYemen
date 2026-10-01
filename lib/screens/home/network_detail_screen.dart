// lib/screens/home/network_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/network_model.dart';
import '../../providers/app_providers.dart';
import '../../utils/app_theme.dart';
import 'purchase_success_screen.dart';

class NetworkDetailScreen extends ConsumerStatefulWidget {
  final Network network;

  const NetworkDetailScreen({super.key, required this.network});

  @override
  ConsumerState<NetworkDetailScreen> createState() =>
      _NetworkDetailScreenState();
}

class _NetworkDetailScreenState extends ConsumerState<NetworkDetailScreen> {
  int? _selectedDenomination;
  bool _isPurchasing = false;

  Future<void> _purchaseCard() async {
    if (_selectedDenomination == null) return;

    final user = ref.read(currentUserProvider);
    if (user == null) {
      _showError('يرجى تسجيل الدخول أولاً');
      return;
    }

    final walletBalance = ref.read(walletBalanceProvider);
    if (walletBalance < _selectedDenomination!) {
      _showError('رصيد غير كافٍ في المحفظة');
      return;
    }

    setState(() => _isPurchasing = true);

    try {
      final service = ref.read(supabaseServiceProvider);

      final result = await service.purchaseCard(
        userId: user.id,
        networkId: widget.network.id,
        denomination: _selectedDenomination!,
      );

      if (result != null && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => PurchaseSuccessScreen(
              cardNumber: result['card_number'] ?? '',
              denomination: _selectedDenomination!,
              networkName: widget.network.name,
            ),
          ),
        );
      }
    } catch (e) {
      _showError('فشلت عملية الشراء: $e');
    } finally {
      setState(() => _isPurchasing = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.network.name),
      ),
      body: Column(
        children: [
          // Network Info Header
          Container(
            padding: const EdgeInsets.all(20),
            color: AppTheme.primary,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: Colors.white,
                      child: Text(
                        widget.network.name.isNotEmpty
                            ? widget.network.name[0]
                            : '?',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.network.name,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.network.locationText,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Denominations
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'اختر الفئة',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: GridView.count(
                      crossAxisCount: 2,
                      childAspectRatio: 1.5,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      children: [200, 500, 1000, 5000].map((denom) {
                        final isSelected = _selectedDenomination == denom;
                        return InkWell(
                          onTap: () {
                            setState(() {
                              _selectedDenomination = denom;
                            });
                          },
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppTheme.primary
                                  : AppTheme.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isSelected
                                    ? AppTheme.primary
                                    : AppTheme.border,
                                width: 2,
                              ),
                            ),
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    '$denom',
                                    style: TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                      color: isSelected
                                          ? Colors.white
                                          : AppTheme.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    'ريال يمني',
                                    style: TextStyle(
                                      color: isSelected
                                          ? Colors.white.withValues(alpha: 0.8)
                                          : AppTheme.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Purchase Button
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _selectedDenomination != null && !_isPurchasing
                    ? _purchaseCard
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                ),
                child: _isPurchasing
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                        _selectedDenomination != null
                            ? 'شراء بـ $_selectedDenomination ر.ي'
                            : 'اختر الفئة أولاً',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
