import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/customer_auth.dart';

abstract interface class CustomerAuthRepository {
  Future<void> signInWithGoogle();
  Future<void> signInWithPhone(String phone);

  Future<AuthResponse> signInWithPhonePassword({
    required String phone,
    required String password,
  });

  Future<AuthResponse> registerTestAccount(
    TestAccountRegistration registration,
  );

  Future<AuthResponse> verifyOtp(String phone, String otp);

  Future<void> signOut();
}

class SupabaseCustomerAuthRepository implements CustomerAuthRepository {
  SupabaseClient get _client => Supabase.instance.client;

  @override
  Future<void> signInWithGoogle() async {
    await _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: 'com.netyemen.customer://login-callback',
      authScreenLaunchMode: LaunchMode.externalApplication,
    );
  }

  @override
  Future<void> signInWithPhone(String phone) async {
    await _client.auth.signInWithOtp(phone: phone);
  }

  @override
  Future<AuthResponse> signInWithPhonePassword({
    required String phone,
    required String password,
  }) {
    return _client.auth.signInWithPassword(
      phone: normalizeYemeniPhone(phone),
      password: password,
    );
  }

  @override
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

  @override
  Future<AuthResponse> verifyOtp(String phone, String otp) {
    return _client.auth.verifyOTP(
      phone: phone,
      token: otp,
      type: OtpType.sms,
    );
  }

  @override
  Future<void> signOut() => _client.auth.signOut();
}
