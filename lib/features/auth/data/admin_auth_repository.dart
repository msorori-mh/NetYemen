import 'package:supabase_flutter/supabase_flutter.dart';

enum AdminAuthEvent { passwordRecovery }

abstract class AdminAuthRepository {
  Stream<AdminAuthEvent> get events;

  Future<void> signIn({required String email, required String password});

  Future<void> requestPasswordRecovery({
    required String email,
    required String redirectUrl,
  });

  Future<void> updatePassword(String password);

  Future<void> signOut();
}

class SupabaseAdminAuthRepository implements AdminAuthRepository {
  final SupabaseClient _client;

  SupabaseAdminAuthRepository(this._client);

  @override
  Stream<AdminAuthEvent> get events => _client.auth.onAuthStateChange
      .where((state) => state.event == AuthChangeEvent.passwordRecovery)
      .map((_) => AdminAuthEvent.passwordRecovery);

  @override
  Future<void> signIn({required String email, required String password}) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  @override
  Future<void> requestPasswordRecovery({
    required String email,
    required String redirectUrl,
  }) async {
    await _client.auth.resetPasswordForEmail(email, redirectTo: redirectUrl);
  }

  @override
  Future<void> updatePassword(String password) async {
    await _client.auth.updateUser(UserAttributes(password: password));
  }

  @override
  Future<void> signOut() => _client.auth.signOut();
}

class DisabledAdminAuthRepository implements AdminAuthRepository {
  const DisabledAdminAuthRepository();

  StateError _unavailable() =>
      StateError('Admin authentication is not configured.');

  @override
  Stream<AdminAuthEvent> get events => const Stream.empty();

  @override
  Future<void> signIn({required String email, required String password}) =>
      Future.error(_unavailable());

  @override
  Future<void> requestPasswordRecovery({
    required String email,
    required String redirectUrl,
  }) => Future.error(_unavailable());

  @override
  Future<void> updatePassword(String password) => Future.error(_unavailable());

  @override
  Future<void> signOut() => Future.error(_unavailable());
}
