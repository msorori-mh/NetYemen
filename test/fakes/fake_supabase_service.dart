import 'package:netyemen/models/user_model.dart';
import 'package:netyemen/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Test-only fake for the Supabase auth boundary. Avoids real network calls and
/// lets tests verify OTP success navigation and profile provisioning without a
/// running Supabase stack.
class FakeSupabaseService extends SupabaseService {
  String? verifyPhone;
  String? verifyOtp;
  User? verifyResult;
  Exception? verifyException;

  bool signOutCalled = false;
  AppUser? profileToReturn;

  @override
  Future<AuthResponse> verifyOTP(String phone, String otp) async {
    verifyPhone = phone;
    verifyOtp = otp;
    if (verifyException != null) {
      throw verifyException!;
    }
    return AuthResponse(
      user: verifyResult,
      session: null,
    );
  }

  @override
  Future<AppUser?> getUserProfile(String userId) async {
    return profileToReturn;
  }

  @override
  Future<void> signOut() async {
    signOutCalled = true;
  }
}
