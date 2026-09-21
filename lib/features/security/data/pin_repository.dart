import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/pin_status.dart';

/// Contract for PIN operations. Implementations must never log or return the
/// plaintext PIN — only pass it through to the backend RPC.
abstract interface class PinRepository {
  /// Resolves the combined server + local-trust state for the current user.
  Future<PinStatus> resolveStatus(String userId);

  /// Enroll a new 6-digit PIN. Throws on `INVALID_PIN` or `PIN_ALREADY_SET`.
  Future<void> setPin(String pin);

  /// Verify a PIN. Returns `true` on match. Throws on `PIN_LOCKED` / `PIN_NOT_SET`.
  Future<bool> verifyPin(String pin);

  /// File a forgot-PIN reset request for admin review.
  Future<void> requestReset();

  /// Mark this device as trusted for [userId].
  Future<void> trustDevice(String userId);
}

class SupabasePinRepository implements PinRepository {
  SupabaseClient get _client => Supabase.instance.client;

  @override
  Future<PinStatus> resolveStatus(String userId) async {
    final hasPin = await _client.rpc('has_account_pin') as bool;
    if (!hasPin) return PinStatus.notSet;

    final prefs = await SharedPreferences.getInstance();
    final trusted = prefs.getString('pin_trusted_$userId') == '1';
    return trusted ? PinStatus.setAndTrusted : PinStatus.setAndUntrusted;
  }

  @override
  Future<void> setPin(String pin) async {
    await _client.rpc('set_account_pin', params: {'p_pin': pin});
  }

  @override
  Future<bool> verifyPin(String pin) async {
    final result =
        await _client.rpc('verify_account_pin', params: {'p_pin': pin});
    return result as bool;
  }

  @override
  Future<void> requestReset() async {
    await _client.rpc('request_pin_reset');
  }

  @override
  Future<void> trustDevice(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pin_trusted_$userId', '1');
  }
}
