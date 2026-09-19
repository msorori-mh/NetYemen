// lib/services/supabase_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';
import '../features/auth/domain/customer_auth.dart';

class SupabaseService {
  SupabaseClient get _client => Supabase.instance.client;

  // ==================== AUTH ====================

  Future<void> signInWithPhone(String phone) async {
    await _client.auth.signInWithOtp(phone: phone);
  }

  Future<AuthResponse> signInWithPhonePassword({
    required String phone,
    required String password,
  }) async {
    return _client.auth.signInWithPassword(
      phone: normalizeYemeniPhone(phone),
      password: password,
    );
  }

  Future<AuthResponse> registerTestAccount(
    TestAccountRegistration registration,
  ) async {
    late final FunctionResponse response;
    try {
      response = await _client.functions.invoke(
        'test-onboarding',
        body: registration.toFunctionBody(),
      );
    } catch (error) {
      final message = error.toString();
      const knownCodes = [
        'ACCOUNT_EXISTS',
        'INVALID_INVITE',
        'TESTER_NOT_ALLOWED',
        'TEST_ONBOARDING_EXPIRED',
        'TEST_ONBOARDING_DISABLED',
      ];
      for (final code in knownCodes) {
        if (message.contains(code)) throw StateError(code);
      }
      rethrow;
    }
    if (response.status < 200 || response.status >= 300) {
      final data = response.data;
      final code = data is Map ? data['error']?.toString() : null;
      throw StateError(code ?? 'ACCOUNT_CREATION_FAILED');
    }

    return signInWithPhonePassword(
      phone: registration.phone,
      password: registration.password,
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

  // ==================== PROFILES ====================
  // V1 identity uses auth.users for authentication and public.profiles for
  // application identity. Profile provisioning is handled automatically by the
  // public.handle_new_user trigger on auth.users insert; client code must not
  // write to or expect a legacy public.users table.

  Future<AppUser?> getUserProfile(String userId) async {
    final response = await _client
        .from('profiles')
        .select(
          'id, full_name, account_status, default_governorate, default_city, created_at',
        )
        .eq('id', userId)
        .maybeSingle();

    if (response == null) return null;

    return AppUser(
      id: response['id'] as String,
      phone: _client.auth.currentUser?.id == userId
          ? (_client.auth.currentUser?.phone ?? '')
          : '',
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
}
