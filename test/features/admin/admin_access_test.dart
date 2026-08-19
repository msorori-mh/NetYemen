import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/features/admin/presentation/admin_access.dart';

void main() {
  group('AdminAccessPolicy', () {
    test('platform admin receives all capabilities', () {
      final capabilities = AdminAccessPolicy.resolve(const ['platform_admin']);

      expect(capabilities, AdminAccessPolicy.allCapabilities);
    });

    test('finance role is limited to money operations', () {
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

    test('support role cannot reach finance or catalog', () {
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

    test('auditor receives overview and audit', () {
      final capabilities = AdminAccessPolicy.resolve(const ['system_auditor']);

      expect(
        capabilities,
        const {
          AdminCapability.overview,
          AdminCapability.audit,
        },
      );
    });

    test('customer and owner have no admin capabilities', () {
      expect(AdminAccessPolicy.resolve(const ['customer']), isEmpty);
      expect(AdminAccessPolicy.resolve(const ['network_owner']), isEmpty);
      expect(AdminAccessPolicy.resolve(const ['network_operator']), isEmpty);
    });

    test('multiple roles combine capabilities', () {
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
