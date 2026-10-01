import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/features/auth/domain/customer_auth.dart';

void main() {
  group('normalizeYemeniPhone', () {
    test('normalizes local, zero-prefixed, and Arabic-digit numbers', () {
      expect(normalizeYemeniPhone('771234567'), '+967771234567');
      expect(normalizeYemeniPhone('0771234567'), '+967771234567');
      expect(normalizeYemeniPhone('٧٧١٢٣٤٥٦٧'), '+967771234567');
    });

    test('rejects a non-Yemeni mobile number', () {
      expect(
        () => normalizeYemeniPhone('12345'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('test account registration', () {
    test('serializes owner as a request without any privileged role field', () {
      const registration = TestAccountRegistration(
        fullName: 'مختبر واصل',
        phone: '771234567',
        password: 'Pilot1234',
        requestedAccountType: RequestedAccountType.networkOwner,
        governorate: 'مأرب',
        city: 'مدينة مأرب',
        latitude: 15.47,
        longitude: 45.32,
        inviteCode: 'TEST-INVITE',
      );

      final body = registration.toFunctionBody();
      expect(body['phone'], '+967771234567');
      expect(body['requested_account_type'], 'network_owner');
      expect(body, isNot(contains('role')));
      expect(body, isNot(contains('phone_confirm')));
    });

    test(
      'password requires at least eight characters, a letter, and a digit',
      () {
        expect(validateTestPassword('short1'), isNotNull);
        expect(validateTestPassword('abcdefgh'), isNotNull);
        expect(validateTestPassword('12345678'), isNotNull);
        expect(validateTestPassword('Pilot1234'), isNull);
      },
    );
  });
}
