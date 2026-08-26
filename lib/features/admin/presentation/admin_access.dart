import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/app_providers.dart';

enum AdminCapability {
  overview,
  support,
  networkRequests,
  networks,
  packages,
  users,
  audit,
  notifications,
  payments,
  settlements,
  cardVault,
}

class AdminAccessPolicy {
  const AdminAccessPolicy._();

  static const Set<AdminCapability> allCapabilities = {
    AdminCapability.overview,
    AdminCapability.support,
    AdminCapability.networkRequests,
    AdminCapability.networks,
    AdminCapability.packages,
    AdminCapability.users,
    AdminCapability.audit,
    AdminCapability.notifications,
    AdminCapability.payments,
    AdminCapability.settlements,
    AdminCapability.cardVault,
  };

  static const Map<String, Set<AdminCapability>> _roleCapabilities = {
    'platform_admin': allCapabilities,
    'finance_officer': {
      AdminCapability.payments,
      AdminCapability.settlements,
    },
    'support_agent': {
      AdminCapability.overview,
      AdminCapability.support,
    },
    'system_auditor': {
      AdminCapability.overview,
      AdminCapability.audit,
    },
  };

  static Set<AdminCapability> resolve(Iterable<String> roles) {
    final capabilities = <AdminCapability>{};
    for (final role in roles) {
      capabilities.addAll(_roleCapabilities[role] ?? const {});
    }
    return Set.unmodifiable(capabilities);
  }
}

final adminCapabilitiesProvider = Provider<Set<AdminCapability>>((ref) {
  final roles = ref.watch(currentUserRolesProvider).value ?? const <String>[];
  return AdminAccessPolicy.resolve(roles);
});

class AdminAccessGate extends ConsumerWidget {
  final Widget child;
  final Set<AdminCapability> anyOf;

  const AdminAccessGate({
    required this.child,
    this.anyOf = AdminAccessPolicy.allCapabilities,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    if (config.isDemoMode) return child;

    final user = ref.watch(currentUserProvider);
    if (user == null) {
      return const _AdminAccessState(
        icon: Icons.lock_outline,
        title: 'يلزم تسجيل الدخول',
        message: 'سجّل الدخول بحساب إداري للوصول إلى لوحة الإدارة.',
      );
    }

    final rolesAsync = ref.watch(currentUserRolesProvider);
    return rolesAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => const _AdminAccessState(
        icon: Icons.error_outline,
        title: 'تعذر التحقق من الصلاحيات',
        message: 'أعد المحاولة بعد التحقق من الاتصال.',
      ),
      data: (roles) {
        final capabilities = AdminAccessPolicy.resolve(roles);
        if (!capabilities.any(anyOf.contains)) {
          return const _AdminAccessState(
            icon: Icons.block_outlined,
            title: 'غير مصرح',
            message: 'لا يملك هذا الحساب صلاحية الوصول إلى لوحة الإدارة.',
          );
        }
        return child;
      },
    );
  }
}

class _AdminAccessState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _AdminAccessState({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('لوحة الإدارة')),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 56, color: AppTheme.primary),
                      const SizedBox(height: 16),
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(message, textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
