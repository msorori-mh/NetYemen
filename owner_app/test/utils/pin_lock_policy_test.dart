import 'package:flutter_test/flutter_test.dart';
import 'package:owner/utils/pin_lock_policy.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final t0 = DateTime(2026, 1, 10, 12);
  const user = 'user-1';

  group('requiresPinEntry', () {
    int millis(DateTime time) => time.millisecondsSinceEpoch;

    test('an untrusted device always needs the PIN', () {
      expect(
        requiresPinEntry(trusted: false, lastActiveMillis: millis(t0), now: t0),
        isTrue,
      );
    });

    test('a trusted device without a recorded activity fails closed', () {
      expect(
        requiresPinEntry(trusted: true, lastActiveMillis: null, now: t0),
        isTrue,
      );
    });

    test('stays unlocked just under 15 minutes of inactivity', () {
      final now = t0.add(const Duration(minutes: 14, seconds: 59));

      expect(
        requiresPinEntry(
          trusted: true,
          lastActiveMillis: millis(t0),
          now: now,
        ),
        isFalse,
      );
    });

    test('locks at exactly 15 minutes and beyond', () {
      expect(
        requiresPinEntry(
          trusted: true,
          lastActiveMillis: millis(t0),
          now: t0.add(pinAutoLockAfter),
        ),
        isTrue,
      );
      expect(
        requiresPinEntry(
          trusted: true,
          lastActiveMillis: millis(t0),
          now: t0.add(const Duration(days: 3)),
        ),
        isTrue,
      );
    });

    test('a clock moved backwards fails closed', () {
      expect(
        requiresPinEntry(
          trusted: true,
          lastActiveMillis: millis(t0),
          now: t0.subtract(const Duration(minutes: 1)),
        ),
        isTrue,
      );
    });
  });

  group('PinLockStore', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      PinLockStore.resetMemoryForTest();
    });

    test('a device that never entered the PIN is locked', () async {
      expect(await PinLockStore.isUnlocked(user, now: t0), isFalse);
    });

    test('a cold start within 15 minutes skips the PIN', () async {
      await PinLockStore.markUnlocked(user, now: t0);
      PinLockStore.resetMemoryForTest(); // the app was killed and relaunched

      final unlocked = await PinLockStore.isUnlocked(
        user,
        now: t0.add(const Duration(minutes: 5)),
      );

      expect(unlocked, isTrue);
    });

    test('a cold start after 15 minutes requires the PIN again', () async {
      await PinLockStore.markUnlocked(user, now: t0);
      PinLockStore.resetMemoryForTest();

      final unlocked = await PinLockStore.isUnlocked(
        user,
        now: t0.add(const Duration(minutes: 16)),
      );

      expect(unlocked, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(pinTrustedKey(user)), isNull);
      // The revoked trust does not come back by itself.
      expect(await PinLockStore.isUnlocked(user, now: t0), isFalse);
    });

    test('backgrounding refreshes the last activity while unlocked', () async {
      await PinLockStore.markUnlocked(user, now: t0);
      await PinLockStore.recordBackgrounded(
        user,
        now: t0.add(const Duration(minutes: 40)),
      );
      PinLockStore.resetMemoryForTest();

      final unlocked = await PinLockStore.isUnlocked(
        user,
        now: t0.add(const Duration(minutes: 50)),
      );

      expect(unlocked, isTrue);
    });

    test('backgrounding from the lock screen does not extend the window',
        () async {
      SharedPreferences.setMockInitialValues({
        pinTrustedKey(user): '1',
        pinLastActiveKey(user): t0.millisecondsSinceEpoch,
      });
      final later = t0.add(const Duration(minutes: 20));

      // Cold start: nothing is unlocked in memory yet.
      await PinLockStore.recordBackgrounded(user, now: later);

      expect(await PinLockStore.isUnlocked(user, now: later), isFalse);
    });

    test('an unlocked session is not interrupted while in the foreground',
        () async {
      await PinLockStore.markUnlocked(user, now: t0);

      final unlocked = await PinLockStore.isUnlocked(
        user,
        now: t0.add(const Duration(hours: 2)),
      );

      expect(unlocked, isTrue);
    });

    test('returning from the background locks only after the timeout',
        () async {
      await PinLockStore.markUnlocked(user, now: t0);
      final left = t0.add(const Duration(minutes: 30));
      await PinLockStore.recordBackgrounded(user, now: left);

      final withinWindow = await PinLockStore.lockIfIdle(
        user,
        now: left.add(const Duration(minutes: 1)),
      );
      expect(withinWindow, isFalse);

      final afterTimeout = await PinLockStore.lockIfIdle(
        user,
        now: left.add(const Duration(minutes: 20)),
      );
      expect(afterTimeout, isTrue);
      expect(await PinLockStore.isUnlocked(user, now: left), isFalse);
    });

    test('lockIfIdle does nothing when the app is already locked', () async {
      final locked = await PinLockStore.lockIfIdle(
        user,
        now: t0.add(const Duration(days: 1)),
      );

      expect(locked, isFalse);
    });

    test('clear forgets every account on the device', () async {
      await PinLockStore.markUnlocked('user-a', now: t0);
      await PinLockStore.markUnlocked('user-b', now: t0);

      await PinLockStore.clear();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
      expect(await PinLockStore.isUnlocked('user-a', now: t0), isFalse);
      expect(await PinLockStore.isUnlocked('user-b', now: t0), isFalse);
    });

    test('unlocking one account does not unlock another', () async {
      await PinLockStore.markUnlocked('user-a', now: t0);

      expect(await PinLockStore.isUnlocked('user-b', now: t0), isFalse);
    });
  });
}
