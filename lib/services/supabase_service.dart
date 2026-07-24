// lib/services/supabase_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';
import '../models/network_model.dart';
import '../models/card_model.dart';

class SupabaseService {
  final _client = Supabase.instance.client;

  // ==================== AUTH ====================

  Future<void> signInWithPhone(String phone) async {
    await _client.auth.signInWithOtp(
      phone: phone,
    );
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

  Future<AppUser?> getUserProfile(String userId) async {
    final response = await _client
        .from('users')
        .select()
        .eq('id', userId)
        .single();

    if (response == null) return null;
    return AppUser.fromJson(response);
  }

  Future<void> createOrUpdateUser({
    required String userId,
    required String phone,
    String? fullName,
  }) async {
    await _client.from('users').upsert({
      'id': userId,
      'phone': phone,
      'full_name': fullName,
      'wallet_balance': 0,
    });
  }

  // ==================== NETWORKS ====================

  Future<List<Network>> getNetworks() async {
    final response = await _client
        .from('networks')
        .select()
        .eq('is_active', true)
        .order('name');

    return (response as List)
        .map((json) => Network.fromJson(json))
        .toList();
  }

  Future<List<NetworkPrice>> getNetworkPrices(String networkId) async {
    final response = await _client
        .from('network_prices')
        .select()
        .eq('network_id', networkId)
        .eq('is_active', true);

    return (response as List)
        .map((json) => NetworkPrice.fromJson(json))
        .toList();
  }

  // ==================== CARDS & PURCHASES ====================

  Future<CardModel?> getAvailableCard({
    required String networkId,
    required int denomination,
  }) async {
    final response = await _client
        .from('cards')
        .select()
        .eq('network_id', networkId)
        .eq('denomination', denomination)
        .eq('status', 'available')
        .order('created_at')
        .limit(1)
        .single();

    if (response == null) return null;
    return CardModel.fromJson(response);
  }

  Future<Map<String, dynamic>?> purchaseCard({
    required String userId,
    required String networkId,
    required int denomination,
  }) async {
    try {
      final result = await _client.rpc('purchase_card', params: {
        'p_user_id': userId,
        'p_network_id': networkId,
        'p_denomination': denomination,
      });

      return result as Map<String, dynamic>?;
    } catch (e) {
      throw Exception('فشل شراء الكرت: $e');
    }
  }

  Future<List<Purchase>> getUserPurchases(String userId) async {
    final response = await _client
        .from('purchases')
        .select('*, networks(name)')
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return (response as List)
        .map((json) => Purchase.fromJson(json))
        .toList();
  }

  // ==================== WALLET ====================

  Future<List<dynamic>> getWalletTransactions(String userId) async {
    final response = await _client
        .from('wallet_transactions')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return response as List;
  }

  Future<void> createDepositRequest({
    required String userId,
    required int amount,
    required String paymentMethod,
  }) async {
    await _client.from('wallet_deposit_requests').insert({
      'user_id': userId,
      'amount': amount,
      'payment_method': paymentMethod,
      'status': 'pending',
    });
  }
}
