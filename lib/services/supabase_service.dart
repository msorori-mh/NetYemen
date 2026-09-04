// lib/services/supabase_service.dart
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/network_model.dart';
import '../models/purchase_model.dart';
import '../models/user_model.dart';
import '../models/wallet_model.dart';

/// Thrown by [SupabaseService.purchaseCard] with an Arabic message already
/// mapped from the RPC's Postgres error code (see NY-BE-005's
/// purchase_card()) — screens can show [message] directly without knowing
/// about SQLSTATE codes.
class PurchaseException implements Exception {
  final String message;
  PurchaseException(this.message);

  @override
  String toString() => message;
}

class SupabaseService {
  final _client = Supabase.instance.client;

  // ==================== AUTH ====================

  Future<void> signInWithPhone(String phone) async {
    await _client.auth.signInWithOtp(phone: phone);
  }

  Future<AuthResponse> verifyOTP(String phone, String otp) async {
    return await _client.auth.verifyOTP(
      phone: phone,
      token: otp,
      type: OtpType.sms,
    );
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  User? get currentUser => _client.auth.currentUser;

  // ==================== USERS ====================
  //
  // No createOrUpdateUser here: the `users` row (and its `wallet_accounts`
  // row) is provisioned automatically by the handle_new_auth_user() database
  // trigger the moment auth.users gets the new row (BR-AUTH-003). A client
  // INSERT into `users` has no matching RLS policy and would simply fail.

  Future<AppUser?> getUserProfile(String userId) async {
    final response =
        await _client.from('users').select().eq('id', userId).maybeSingle();

    if (response == null) return null;
    return AppUser.fromJson(response);
  }

  // ==================== NETWORKS ====================

  Future<List<Network>> getNetworks() async {
    // is_approved AND is_active both gate customer discovery (BR-NETWORK-005);
    // RLS enforces this too, but filtering here keeps the query itself honest.
    final response = await _client
        .from('networks')
        .select('*, network_ssids(ssid)')
        .eq('is_approved', true)
        .eq('is_active', true)
        .order('name');

    return (response as List).map((json) => Network.fromJson(json)).toList();
  }

  Future<List<NetworkPrice>> getNetworkPrices(String networkId) async {
    final response = await _client
        .from('network_prices')
        .select()
        .eq('network_id', networkId)
        .eq('is_active', true)
        .order('denomination');

    return (response as List)
        .map((json) => NetworkPrice.fromJson(json))
        .toList();
  }

  // ==================== PURCHASES ====================

  /// Calls the atomic purchase_card RPC (NY-BE-005). There is no user id or
  /// price parameter to pass — the server derives the buyer from the JWT and
  /// looks the price up itself (BR-PURCHASE-003/004). [idempotencyKey] should
  /// be a fresh UUID per purchase attempt; retrying the exact same key after
  /// a network failure safely replays the original result instead of
  /// double-charging (BR-PURCHASE-002).
  Future<PurchaseResult> purchaseCard({
    required String networkId,
    required String networkPriceId,
    required String idempotencyKey,
  }) async {
    try {
      final result = await _client.rpc('purchase_card', params: {
        'p_network_id': networkId,
        'p_network_price_id': networkPriceId,
        'p_idempotency_key': idempotencyKey,
      });

      final row = (result as List).first as Map<String, dynamic>;
      return PurchaseResult.fromJson(row);
    } on PostgrestException catch (e) {
      throw PurchaseException(_friendlyPurchaseError(e));
    }
  }

  String _friendlyPurchaseError(PostgrestException e) {
    switch (e.code) {
      case '23514':
        return 'رصيد المحفظة غير كافٍ لإتمام عملية الشراء';
      case 'P0003':
        return 'نفدت الكمية المتاحة لهذه الفئة حالياً، جرّب فئة أخرى';
      case '22023':
        return 'هذه الشبكة أو الفئة غير متاحة حالياً';
      case '42501':
        return 'حسابك غير نشط، يرجى التواصل مع الدعم';
      case '28000':
        return 'يرجى تسجيل الدخول مجدداً';
      default:
        return 'تعذّر إتمام عملية الشراء، حاول مرة أخرى';
    }
  }

  /// COND-6 re-reveal of an already-purchased card (e.g. from the Purchases
  /// screen). Never cache the return value beyond the immediate display.
  Future<String> revealPurchasedCard(String purchaseId) async {
    final result = await _client.rpc('reveal_purchased_card', params: {
      'p_purchase_id': purchaseId,
    });
    return result as String;
  }

  Future<List<Purchase>> getUserPurchases(String userId) async {
    final response = await _client
        .from('purchases')
        .select('*, networks(name)')
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return (response as List).map((json) => Purchase.fromJson(json)).toList();
  }

  // ==================== WALLET ====================

  Future<int> getWalletBalance(String userId) async {
    final response = await _client
        .from('wallet_accounts')
        .select('cached_balance')
        .eq('user_id', userId)
        .maybeSingle();

    return response?['cached_balance'] ?? 0;
  }

  Future<List<WalletLedgerEntry>> getWalletLedger(String userId) async {
    final response = await _client
        .from('wallet_ledger_entries')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return (response as List)
        .map((json) => WalletLedgerEntry.fromJson(json))
        .toList();
  }

  Future<List<BankAccount>> getBankAccounts() async {
    final response = await _client
        .from('bank_accounts')
        .select()
        .eq('is_active', true)
        .order('display_order');

    return (response as List)
        .map((json) => BankAccount.fromJson(json))
        .toList();
  }

  /// Uploads a deposit receipt photo to the `deposit-receipts` Storage
  /// bucket and returns the storage path to pass to [createDepositRequest].
  ///
  /// NOTE: as of NY-BE-004 no such bucket (or its RLS-equivalent storage
  /// policies) has been created yet — that is backend/`supabase/` scope,
  /// out of bounds for this task's Allowed Files. This call will fail with
  /// a bucket-not-found error until a follow-up backend migration adds it.
  Future<String> uploadDepositReceipt({
    required String userId,
    required Uint8List bytes,
    required String fileExtension,
  }) async {
    final path =
        '$userId/${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
    await _client.storage.from('deposit-receipts').uploadBinary(path, bytes);
    return path;
  }

  Future<void> createDepositRequest({
    required String userId,
    required int amount,
    required String depositChannel,
    required String receiptImagePath,
  }) async {
    await _client.from('wallet_deposit_requests').insert({
      'user_id': userId,
      'amount': amount,
      'deposit_channel': depositChannel,
      'receipt_image_path': receiptImagePath,
    });
  }
}
