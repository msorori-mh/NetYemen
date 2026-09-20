import 'package:netyemen/features/auth/data/customer_auth_repository.dart';
import 'package:netyemen/features/auth/domain/customer_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeCustomerAuthRepository implements CustomerAuthRepository {
  String? otpPhone;
  String? otpValue;
  User? otpResult;
  Exception? otpException;

  String? passwordPhone;
  String? passwordValue;
  User? passwordResult;
  Exception? passwordException;

  String? phoneOtpRequest;
  Exception? phoneOtpException;

  TestAccountRegistration? registration;
  User? registrationResult;
  Exception? registrationException;

  bool signOutCalled = false;
  Exception? signOutException;

  @override
  Future<void> signInWithPhone(String phone) async {
    phoneOtpRequest = phone;
    if (phoneOtpException != null) throw phoneOtpException!;
  }

  @override
  Future<AuthResponse> verifyOtp(String phone, String otp) async {
    otpPhone = phone;
    otpValue = otp;
    if (otpException != null) throw otpException!;
    return AuthResponse(user: otpResult, session: null);
  }

  @override
  Future<AuthResponse> signInWithPhonePassword({
    required String phone,
    required String password,
  }) async {
    passwordPhone = phone;
    passwordValue = password;
    if (passwordException != null) throw passwordException!;
    return AuthResponse(user: passwordResult, session: null);
  }

  @override
  Future<AuthResponse> registerTestAccount(
    TestAccountRegistration value,
  ) async {
    registration = value;
    if (registrationException != null) throw registrationException!;
    return AuthResponse(user: registrationResult, session: null);
  }

  @override
  Future<void> signOut() async {
    signOutCalled = true;
    if (signOutException != null) throw signOutException!;
  }
}
