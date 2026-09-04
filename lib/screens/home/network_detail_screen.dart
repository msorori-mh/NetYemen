// lib/screens/home/network_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../models/network_model.dart';
import '../../providers/app_providers.dart';
import '../../services/supabase_service.dart';
import '../../utils/app_theme.dart';
import 'purchase_success_screen.dart';

const _uuid = Uuid();

class NetworkDetailScreen extends ConsumerStatefulWidget {
  final Network network;

  const NetworkDetailScreen({super.key, required this.network});

  @override
  ConsumerState<NetworkDetailScreen> createState() =>
      _NetworkDetailScreenState();
}

class _NetworkDetailScreenState extends ConsumerState<NetworkDetailScreen> {
  NetworkPrice? _selectedPrice;
  bool _isPurchasing = false;

  Future<void> _confirmAndPurchase() async {
    final price = _selectedPrice;
    if (price == null) return;

    final user = ref.read(currentUserProvider);
    if (user == null) {
      _showError('يرجى تسجيل الدخول أولاً');
      return;
    }

    final confirmed = await _showPurchaseConfirmationModal(price);
    if (confirmed != true || !mounted) return;

    setState(() => _isPurchasing = true);

    try {
      final service = ref.read(supabaseServiceProvider);
      final result = await service.purchaseCard(
        networkId: widget.network.id,
        networkPriceId: price.id,
        idempotencyKey: _uuid.v4(),
      );

      // The purchase moved money and stock — refresh both so the wallet
      // screen and purchases list don't show stale state on return.
      ref.invalidate(walletBalanceProvider);
      ref.invalidate(walletLedgerProvider);
      ref.invalidate(userPurchasesProvider);

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => PurchaseSuccessScreen(
            cardNumber: result.cardNumber,
            pricePaid: result.pricePaid,
            networkName: widget.network.name,
          ),
        ),
      );
    } on PurchaseException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('تعذّر إتمام عملية الشراء');
    } finally {
      if (mounted) setState(() => _isPurchasing = false);
    }
  }

  Future<bool?> _showPurchaseConfirmationModal(NetworkPrice price) {
    final balanceAsync = ref.read(walletBalanceProvider);
    final balance = balanceAsync.asData?.value ?? 0;
    final insufficientBalance = balance < price.sellingPrice;

    return showModalBottomSheet<bool>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'تأكيد الشراء',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              _confirmationRow('الشبكة', widget.network.name),
              _confirmationRow('الفئة', '${price.denomination} ر.ي'),
              _confirmationRow('البيانات', price.dataQuotaLabel),
              _confirmationRow('الصلاحية', price.validityLabel),
              const Divider(height: 32),
              _confirmationRow(
                'السعر',
                '${price.sellingPrice} ر.ي',
                emphasize: true,
              ),
              _confirmationRow('رصيدك الحالي', '$balance ر.ي'),
              if (insufficientBalance) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.error_outline, color: AppTheme.error, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'رصيدك غير كافٍ لإتمام هذه العملية',
                          style: TextStyle(color: AppTheme.error, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: insufficientBalance
                      ? null
                      : () => Navigator.pop(sheetContext, true),
                  child: const Text('تأكيد الشراء'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(sheetContext, false),
                  child: const Text('إلغاء'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _confirmationRow(String label, String value, {bool emphasize = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppTheme.textSecondary)),
          Text(
            value,
            style: TextStyle(
              fontWeight: emphasize ? FontWeight.bold : FontWeight.w600,
              fontSize: emphasize ? 18 : 14,
              color: emphasize ? AppTheme.primary : AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pricesAsync = ref.watch(networkPricesProvider(widget.network.id));

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
                            widget.network.displayLocation,
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

          // Price Tiers (dynamic — fetched from network_prices, never hard-coded)
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
                    child: pricesAsync.when(
                      data: (prices) {
                        if (prices.isEmpty) {
                          return const Center(
                            child: Text('لا توجد فئات متاحة لهذه الشبكة حالياً'),
                          );
                        }

                        return GridView.builder(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 1.3,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          itemCount: prices.length,
                          itemBuilder: (context, index) {
                            final price = prices[index];
                            final isSelected = _selectedPrice?.id == price.id;
                            return InkWell(
                              onTap: () {
                                setState(() => _selectedPrice = price);
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
                                        '${price.sellingPrice}',
                                        style: TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                          color: isSelected
                                              ? Colors.white
                                              : AppTheme.textPrimary,
                                        ),
                                      ),
                                      Text(
                                        'ريال يمني',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isSelected
                                              ? Colors.white.withValues(alpha: 0.8)
                                              : AppTheme.textSecondary,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${price.dataQuotaLabel} · ${price.validityLabel}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isSelected
                                              ? Colors.white.withValues(alpha: 0.7)
                                              : AppTheme.textMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (_, __) =>
                          const Center(child: Text('تعذّر تحميل الفئات')),
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
                onPressed: _selectedPrice != null && !_isPurchasing
                    ? _confirmAndPurchase
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                ),
                child: _isPurchasing
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                        _selectedPrice != null
                            ? 'شراء بـ ${_selectedPrice!.sellingPrice} ر.ي'
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
