import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:owner/utils/error_text.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Built through helpers so the tests do not depend on these constructors
// being const.
PostgrestException postgrestError(String message, {String? code}) {
  return PostgrestException(message: message, code: code);
}

AuthException authError(String message) => AuthException(message);

void main() {
  group('friendlyErrorText', () {
    test('maps known server codes to Arabic messages', () {
      final forbidden = postgrestError(
        'FORBIDDEN_ROLE: Only network owners may ingest cards',
        code: 'P0001',
      );
      final inactive = postgrestError(
        'INACTIVE_PROFILE: profile is not active',
      );
      final unauthenticated = postgrestError(
        'UNAUTHENTICATED: Authentication required',
      );

      expect(
        friendlyErrorText(forbidden),
        'حسابك لا يملك صلاحية تنفيذ هذا الإجراء.',
      );
      expect(
        friendlyErrorText(inactive),
        'حسابك غير مفعّل. تواصل مع فريق واصل نت.',
      );
      expect(
        friendlyErrorText(unauthenticated),
        'انتهت جلستك. سجّل الدخول من جديد.',
      );
    });

    test('maps the card ingestion codes', () {
      final invalidCard = postgrestError('INVALID_CARD: bad pin');
      final tooMany = postgrestError('TOO_MANY_CARDS: 5001');

      expect(friendlyErrorText(invalidCard), contains('64'));
      expect(friendlyErrorText(tooMany), contains('5000'));
    });

    test('any other INVALID_* code becomes a generic validation message', () {
      final error = postgrestError('INVALID_SOMETHING_NEW: x');

      expect(
        friendlyErrorText(error),
        'البيانات المدخلة غير صالحة. راجعها وحاول مرة أخرى.',
      );
    });

    test('maps PIN lockout', () {
      final error = postgrestError('PIN_LOCKED: try later');

      expect(friendlyErrorText(error), contains('15'));
    });

    test('maps Postgres SQLSTATE codes when there is no named code', () {
      final duplicate = postgrestError(
        'duplicate key value violates unique constraint "x"',
        code: '23505',
      );
      final rls = postgrestError(
        'new row violates row-level security policy',
        code: '42501',
      );

      expect(friendlyErrorText(duplicate), 'هذا العنصر موجود مسبقاً.');
      expect(
        friendlyErrorText(rls),
        'حسابك لا يملك صلاحية تنفيذ هذا الإجراء.',
      );
    });

    test('recognises network failures', () {
      final lookup = Exception(
        "ClientException with SocketException: Failed host lookup: 'x.co'",
      );

      expect(friendlyErrorText(lookup), networkErrorText);
      expect(
        friendlyErrorText(TimeoutException('no answer')),
        networkErrorText,
      );
    });

    test('reads the code from an AuthException message', () {
      final error = authError('UNAUTHENTICATED: session expired');

      expect(friendlyErrorText(error), 'انتهت جلستك. سجّل الدخول من جديد.');
    });

    test('never shows the raw text of an unknown error', () {
      const raw = 'relation "public.secret_table" does not exist';
      final error = postgrestError(raw, code: '42P01');

      final text = friendlyErrorText(error);

      expect(text, genericErrorText);
      expect(text, isNot(contains('secret_table')));
      expect(friendlyErrorText(StateError('boom')), genericErrorText);
    });

    test('uses the caller fallback for unknown errors', () {
      expect(
        friendlyErrorText(StateError('boom'), fallback: 'تعذّر الحفظ'),
        'تعذّر الحفظ',
      );
    });
  });

  group('describeError', () {
    test('returns the same friendly text it logs for', () {
      final error = postgrestError('NOT_FOUND: package');

      expect(
        describeError(error, stackTrace: StackTrace.current, where: 'test'),
        friendlyErrorText(error),
      );
    });
  });
}
