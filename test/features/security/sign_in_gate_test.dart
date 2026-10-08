import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/features/security/presentation/sign_in_gate.dart';

void main() {
  group('SignedInGateTracker', () {
    test('an unclaimed sign-in must pass the PIN gate', () {
      // This is the Google OAuth return: no screen is waiting for it.
      final tracker = SignedInGateTracker();

      expect(tracker.onSignedIn('user-a', claimedByScreen: false), isTrue);
      expect(tracker.gatedUserId, 'user-a');
    });

    test('a sign-in routed by its own screen is not gated twice', () {
      final tracker = SignedInGateTracker();

      expect(tracker.onSignedIn('user-a', claimedByScreen: true), isFalse);
      expect(tracker.gatedUserId, 'user-a');
    });

    test('repeated events for the same account never restart the gate', () {
      final tracker = SignedInGateTracker();

      expect(tracker.onSignedIn('user-a', claimedByScreen: false), isTrue);
      expect(tracker.onSignedIn('user-a', claimedByScreen: false), isFalse);
      expect(tracker.onSignedIn('user-a', claimedByScreen: false), isFalse);
    });

    test('a session restored at startup is left to the root gate', () {
      final tracker = SignedInGateTracker(initialUserId: 'user-a');

      expect(tracker.onSignedIn('user-a', claimedByScreen: false), isFalse);
    });

    test('a different account is gated', () {
      final tracker = SignedInGateTracker(initialUserId: 'user-a');

      expect(tracker.onSignedIn('user-b', claimedByScreen: false), isTrue);
    });

    test('the same account is gated again after a sign-out', () {
      final tracker = SignedInGateTracker(initialUserId: 'user-a');

      tracker.onSignedOut();

      expect(tracker.gatedUserId, isNull);
      expect(tracker.onSignedIn('user-a', claimedByScreen: false), isTrue);
    });

    test('an event without an account is ignored', () {
      final tracker = SignedInGateTracker();

      expect(tracker.onSignedIn(null, claimedByScreen: false), isFalse);
      expect(tracker.onSignedIn('', claimedByScreen: false), isFalse);
      expect(tracker.gatedUserId, isNull);
    });
  });
}
