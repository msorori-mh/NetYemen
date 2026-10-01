// lib/services/owner_supabase_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/owned_network_model.dart';

/// طبقة الوصول إلى Supabase لتطبيق أصحاب الشبكات.
///
/// نفس تصميم تطبيق العميل: **RPC أولاً**. تسجيل الدخول بهاتف مصادَق نفسه،
/// لكن الوصول إلى التطبيق مقيّد بعده بحاجز دور صاحب شبكة — راجع
/// [getOwnedNetworks] والتعليق على استخدامها في شاشة البداية.
class OwnerSupabaseService {
  final SupabaseClient _client = Supabase.instance.client;

  // ==================== AUTH ====================

  static const String _oauthRedirect = 'com.netyemen.owner://login-callback';

  Future<void> signInWithGoogle() async {
    await _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: _oauthRedirect,
      authScreenLaunchMode: LaunchMode.externalApplication,
    );
  }

  Future<void> signOut() async => await _client.auth.signOut();

  User? get currentUser => _client.auth.currentUser;

  // ==================== OWNER ====================

  /// شبكات المستخدم الحالي عبر `get_owned_networks()`.
  ///
  /// تُعيد `[]` لأي مستخدم مصادَق لا يملك عضوية `owner` نشطة على أي شبكة —
  /// هذا هو حاجز الدور: مصادقة ناجحة + قائمة فارغة تعني "ليس صاحب شبكة"،
  /// وليس خطأً. لا يوجد دور "network_owner" منفصل يُتحقق منه مسبقاً؛ الدالة
  /// نفسها تتحقق منه داخلياً وتُعيد الصفوف المطابقة فقط.
  Future<List<OwnedNetwork>> getOwnedNetworks() async {
    final response = await _client.rpc('get_owned_networks');
    return (response as List)
        .map((json) => OwnedNetwork.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<bool> hasPlatformRole(String role) async {
    final response = await _client.rpc('has_platform_role', params: {'p_role': role});
    return response == true;
  }

  Future<String> createNetworkDraft({
    required String commercialName,
    required String governorate,
    String? description,
    String? city,
    String? district,
  }) async {
    final response = await _client.rpc('create_network_draft', params: {
      'p_commercial_name': commercialName,
      'p_description': description,
      'p_governorate': governorate,
      'p_city': city,
      'p_district': district,
    });
    return response.toString();
  }

  // ==================== PIN ====================

  Future<bool> hasAccountPin() async {
    final response = await _client.rpc('has_account_pin');
    return response == true;
  }

  Future<void> setAccountPin(String pin) async {
    await _client.rpc('set_account_pin', params: {'p_pin': pin});
  }

  Future<bool> verifyAccountPin(String pin) async {
    final response = await _client.rpc('verify_account_pin', params: {'p_pin': pin});
    return response == true;
  }

  Future<String> requestPinReset() async {
    final response = await _client.rpc('request_pin_reset');
    return response.toString();
  }
}
