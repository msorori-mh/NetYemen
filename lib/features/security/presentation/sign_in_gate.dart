import 'package:flutter_riverpod/flutter_riverpod.dart';

/// True while a screen is signing a user in and will route to the PIN gate
/// itself (password login, test sign-up, SMS code).
///
/// The app root routes every other sign-in — most importantly the Google
/// OAuth return, which no screen is waiting for — through the PIN gate. A
/// sign-in nobody claimed is always gated, so a new sign-in path cannot skip
/// the PIN by accident.
final screenRoutedSignInProvider = StateProvider<bool>((ref) => false);

/// Decides, from auth events alone, when the app root must show the PIN gate.
///
/// It remembers which account has already been sent to the gate so repeated
/// or replayed "signed in" events for the same account never restart it
/// (no navigation loops), while a different account — or the same account
/// after a sign-out — is gated again.
class SignedInGateTracker {
  SignedInGateTracker({String? initialUserId}) : _gatedUserId = initialUserId;

  String? _gatedUserId;

  /// The account most recently sent to the PIN gate, if any.
  String? get gatedUserId => _gatedUserId;

  /// Records a "signed in" event for [userId].
  ///
  /// Returns true when the app root must navigate to the PIN gate: the
  /// account is new to this tracker and no screen claimed the sign-in.
  bool onSignedIn(String? userId, {required bool claimedByScreen}) {
    if (userId == null || userId.isEmpty) return false;
    if (userId == _gatedUserId) return false;
    _gatedUserId = userId;
    return !claimedByScreen;
  }

  /// Records a sign-out: the next sign-in of any account is gated again.
  void onSignedOut() => _gatedUserId = null;
}
