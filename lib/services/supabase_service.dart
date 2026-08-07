// lib/services/supabase_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';
import '../models/network_model.dart';
import '../models/card_model.dart';

class SupabaseService {
  SupabaseClient get _client => Supabase.instance.client;

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

  // ==================== PROFILES ====================
  // V1 identity uses auth.users for authentication and public.profiles for
  // application identity. Profile provisioning is handled automatically by the
  // public.handle_new_user trigger on auth.users insert; client code must not
  // write to or expect a legacy public.users table.

  Future<AppUser?> getUserProfile(String userId) async {
    final response = await _client
        .from('profiles')
        .select('id, full_name, account_status, default_governorate, default_city, created_at')
        .eq('id', userId)
        .maybeSingle();

    if (response == null) return null;

    return AppUser(
      id: response['id'] as String,
      phone: '',
      fullName: response['full_name'] as String?,
      role: 'customer',
      walletBalance: 0,
      governorate: response['default_governorate'] as String?,
      city: response['default_city'] as String?,
      isActive: response['account_status'] == 'active',
      createdAt: response['created_at'] != null
          ? DateTime.parse(response['created_at'] as String)
          : null,
    );
  }

  // ==================== NETWORKS ====================

  Future<List<Network>> getNetworks() async {
    final response = await _client
        .from('networks')
        .select()
        .eq('is_active', true)
        .order('name');

    return (response as List).map((json) => Network.fromJson(json)).toList();
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
        .maybeSingle();

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

    return (response as List).map((json) => Purchase.fromJson(json)).toList();
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
