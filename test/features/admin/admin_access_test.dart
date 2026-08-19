import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/features/admin/presentation/admin_access.dart';

void main() {
  group('AdminAccessPolicy', () {
    test('platform admin receives the complete console capability set', () {
      final capabilities = AdminAccessPolicy.resolve(const ['platform_admin']);

      expect(capabilities, AdminAccessPolicy.allCapabilities);
    });

    test('finance officer is isolated to payment and settlement operations', () {
      final capabilities = AdminAccessPolicy.resolve(const ['finance_officer']);

      expect(
        capabilities,
        const {
          AdminCapability.payments,
          AdminCapability.settlements,
        },
      );
      expect(capabilities.contains(AdminCapability.users), isFalse);
      expect(capabilities.contains(AdminCapability.cardVault), isFalse);
    });

    test('support agent cannot reach finance or catalog administration', () {
      final capabilities = AdminAccessPolicy.resolve(const ['support_agent']);

      expect(
        capabilities,
        const {
          AdminCapability.overview,
          AdminCapability.support,
        },
      );
      expect(capabilities.contains(AdminCapability.payments), isFalse);
      expect(capabilities.contains(AdminCapability.networks), isFalse);
    });

    test('system auditor receives read-only overview and audit capabilities', () {
      final capabilities = AdminAccessPolicy.resolve(const ['system_auditor']);

      expect(
        capabilities,
        const {
          AdminCapability.overview,
          AdminCapability.audit,
        },
      );
    });

    test('customer and owner roles receive no admin capabilities', () {
      expect(AdminAccessPolicy.resolve(const ['customer']), isEmpty);
      expect(AdminAccessPolicy.resolve(const ['network_owner']), isEmpty);
      expect(AdminAccessPolicy.resolve(const ['network_operator']), isEmpty);
    });

    test('multiple roles produce the union of their capabilities', () {
      final capabilities = AdminAccessPolicy.resolve(
        const ['support_agent', 'finance_officer'],
      );

      expect(
        capabilities,
        const {
          AdminCapability.overview,
          AdminCapability.support,
          AdminCapability.payments,
          AdminCapability.settlements,
        },
      );
    });
  });
}
