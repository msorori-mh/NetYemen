// lib/services/supabase_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';
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
}
