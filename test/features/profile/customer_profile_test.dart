import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/features/profile/domain/customer_profile.dart';

void main() {
  group('CustomerProfile.fromJson', () {
    test('maps the public profile contract', () {
      final profile = CustomerProfile.fromJson({
        'id': 'profile-1',
        'full_name': 'أحمد محمد',
        'account_status': 'active',
        'default_governorate': 'مأرب',
        'default_city': 'مدينة مأرب',
        'created_at': '2026-09-19T12:00:00.000Z',
      });

      expect(profile.id, 'profile-1');
      expect(profile.fullName, 'أحمد محمد');
      expect(profile.governorate, 'مأرب');
      expect(profile.city, 'مدينة مأرب');
      expect(profile.isActive, isTrue);
      expect(
        profile.createdAt,
        DateTime.parse('2026-09-19T12:00:00.000Z'),
      );
    });

    test('treats missing or unknown account status as inactive', () {
      expect(CustomerProfile.fromJson(const {}).isActive, isFalse);
      expect(
        CustomerProfile.fromJson(
          const {'account_status': 'suspended'},
        ).isActive,
        isFalse,
      );
    });
  });
}
