// lib/utils/pin_lock_policy.dart
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// مدة الخمول التي يُطلب بعدها رمز الدخول من جديد.
const Duration pinAutoLockAfter = Duration(minutes: 15);

const String _trustedPrefix = 'pin_trusted_';
const String _lastActivePrefix = 'pin_last_active_';

String pinTrustedKey(String userId) => '$_trustedPrefix$userId';
String pinLastActiveKey(String userId) => '$_lastActivePrefix$userId';

/// القرار النقي: هل يجب طلب رمز الدخول الآن؟
///
/// يفشل مغلقاً: أي معلومة ناقصة أو غير منطقية (لا توجد علامة ثقة، لا يوجد
/// وقت آخر نشاط، أو ساعة الجهاز عادت إلى الوراء) تعني طلب الرمز.
bool requiresPinEntry({
  required bool trusted,
  required int? lastActiveMillis,
  required DateTime now,
  Duration lockAfter = pinAutoLockAfter,
}) {
  if (!trusted) return true;
  if (lastActiveMillis == null) return true;
  final elapsed = now.millisecondsSinceEpoch - lastActiveMillis;
  if (elapsed < 0) return true;
  return elapsed >= lockAfter.inMilliseconds;
}

/// حالة قفل رمز الدخول على هذا الجهاز.
///
/// تُحفظ علامة الثقة ووقت آخر نشاط في SharedPreferences حتى لا يتجاوز إغلاق
/// التطبيق وإعادة فتحه مهلة الـ 15 دقيقة. الذاكرة تحتفظ فقط بهوية المستخدم
/// الذي فُتح له القفل في هذه العملية.
class PinLockStore {
  PinLockStore._();

  static String? _unlockedUserId;

  /// هل القفل مفتوح لهذا المستخدم الآن؟ (يُستدعى عند بدء التشغيل.)
  static Future<bool> isUnlocked(String userId, {DateTime? now}) async {
    if (_unlockedUserId == userId) return true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final trusted = prefs.getString(pinTrustedKey(userId)) == '1';
      final locked = requiresPinEntry(
        trusted: trusted,
        lastActiveMillis: prefs.getInt(pinLastActiveKey(userId)),
        now: now ?? DateTime.now(),
      );
      if (locked) {
        if (trusted) await prefs.remove(pinTrustedKey(userId));
        return false;
      }
      _unlockedUserId = userId;
      return true;
    } catch (error, stackTrace) {
      _log('isUnlocked', error, stackTrace);
      return false;
    }
  }

  /// يُستدعى بعد إدخال/إعداد رمز صحيح.
  static Future<void> markUnlocked(String userId, {DateTime? now}) async {
    _unlockedUserId = userId;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        pinLastActiveKey(userId),
        (now ?? DateTime.now()).millisecondsSinceEpoch,
      );
      await prefs.setString(pinTrustedKey(userId), '1');
    } catch (error, stackTrace) {
      // القفل مفتوح لهذه العملية فقط؛ التشغيل القادم سيطلب الرمز.
      _log('markUnlocked', error, stackTrace);
    }
  }

  /// يسجّل وقت مغادرة التطبيق للواجهة. لا يفعل شيئاً إن كان القفل مغلقاً،
  /// حتى لا تُمدَّد المهلة من شاشة إدخال الرمز نفسها.
  static Future<void> recordBackgrounded(String userId, {DateTime? now}) async {
    if (_unlockedUserId != userId) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        pinLastActiveKey(userId),
        (now ?? DateTime.now()).millisecondsSinceEpoch,
      );
    } catch (error, stackTrace) {
      _log('recordBackgrounded', error, stackTrace);
    }
  }

  /// يُستدعى عند العودة للواجهة. يعيد `true` إذا كان القفل مفتوحاً وانتهت
  /// المهلة (فيُسحب فتح القفل ويجب عرض شاشة الرمز). يعيد `false` إذا كان
  /// القفل مغلقاً أصلاً أو لم تنتهِ المهلة.
  static Future<bool> lockIfIdle(String userId, {DateTime? now}) async {
    if (_unlockedUserId != userId) return false;
    var expired = true;
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      expired = requiresPinEntry(
        trusted: prefs.getString(pinTrustedKey(userId)) == '1',
        lastActiveMillis: prefs.getInt(pinLastActiveKey(userId)),
        now: now ?? DateTime.now(),
      );
    } catch (error, stackTrace) {
      _log('lockIfIdle', error, stackTrace);
    }
    if (!expired) return false;

    _unlockedUserId = null;
    try {
      await prefs?.remove(pinTrustedKey(userId));
    } catch (error, stackTrace) {
      _log('lockIfIdle.remove', error, stackTrace);
    }
    return true;
  }

  /// ينسى كل علامات الثقة على هذا الجهاز (عند تسجيل الخروج أو غياب الجلسة)،
  /// فيُطلب الرمز دائماً بعد أي تسجيل دخول جديد.
  static Future<void> clear() async {
    _unlockedUserId = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys().toList()) {
        if (key.startsWith(_trustedPrefix) ||
            key.startsWith(_lastActivePrefix)) {
          await prefs.remove(key);
        }
      }
    } catch (error, stackTrace) {
      _log('clear', error, stackTrace);
    }
  }

  @visibleForTesting
  static void resetMemoryForTest() => _unlockedUserId = null;

  static void _log(String where, Object error, StackTrace stackTrace) {
    developer.log(
      'PIN lock storage failed',
      name: 'owner.pin_lock.$where',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
