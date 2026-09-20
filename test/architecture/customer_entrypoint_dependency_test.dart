import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('customer entrypoint excludes privileged presentation surfaces', () {
    const deniedPaths = <String>{
      'lib/features/admin/presentation/',
      'lib/features/finance/presentation/',
      'lib/features/packages/presentation/owner_',
    };

    final visited = <String>{};
    final pending = <String>['lib/main.dart'];

    while (pending.isNotEmpty) {
      final path = pending.removeLast();
      if (!visited.add(path)) continue;

      for (final deniedPath in deniedPaths) {
        expect(
          path.startsWith(deniedPath),
          isFalse,
          reason: 'Customer dependency graph reached $path via lib/main.dart',
        );
      }

      final source = File(path).readAsStringSync();
      final directives = RegExp(
        r'''(?:import|export)\s+['"]([^'"]+)['"]''',
      );

      for (final match in directives.allMatches(source)) {
        final uri = match.group(1)!;
        final dependency = _resolveProjectDependency(path, uri);
        if (dependency != null) pending.add(dependency);
      }
    }

    expect(visited, contains('lib/app/app_shell.dart'));
    expect(
      visited,
      contains('lib/features/profile/presentation/profile_screen.dart'),
    );
    expect(File('lib/admin_main.dart').existsSync(), isTrue);
  });

  test('shared app configuration is not owned by a feature', () {
    final providerSource =
        File('lib/core/config/app_config_provider.dart').readAsStringSync();
    expect(providerSource, contains('final appConfigProvider'));

    final misplacedOwners = Directory('lib/features')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where(
          (file) =>
              file.readAsStringSync().contains('final appConfigProvider ='),
        )
        .map((file) => file.path)
        .toList();

    expect(
      misplacedOwners,
      isEmpty,
      reason: 'Shared configuration must stay in core: $misplacedOwners',
    );
  });

  test('customer session providers are owned by auth feature', () {
    final sessionSource = File(
      'lib/features/auth/presentation/customer_session_providers.dart',
    ).readAsStringSync();
    expect(sessionSource, contains('final authStateProvider'));
    expect(sessionSource, contains('final currentUserProvider'));
    expect(sessionSource, contains('final currentUserRolesProvider'));

    final remainingFeatureImports = Directory('lib/features')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where(
          (file) =>
              file.readAsStringSync().contains("providers/app_providers.dart'"),
        )
        .map((file) => file.path.replaceAll('\\', '/'))
        .toList();

    expect(
      remainingFeatureImports,
      isEmpty,
      reason: 'Features must depend on owned providers, not the legacy facade.',
    );
  });

  test('customer profile provider is owned by profile feature', () {
    final profileSource = File(
      'lib/features/profile/presentation/customer_profile_providers.dart',
    ).readAsStringSync();
    expect(profileSource, contains('final userProfileProvider'));

    expect(File('lib/providers/app_providers.dart').existsSync(), isFalse);
  });

  test('customer auth screens are owned by auth feature', () {
    const screenNames = ['login', 'signup', 'otp'];
    for (final name in screenNames) {
      final canonical =
          File('lib/features/auth/presentation/${name}_screen.dart');

      expect(
        canonical.existsSync(),
        isTrue,
        reason: 'Missing ${canonical.path}',
      );
      expect(
        File('lib/screens/auth/${name}_screen.dart').existsSync(),
        isFalse,
        reason: 'Retired compatibility screen must stay deleted: $name',
      );
    }

    final legacyImports = Directory('lib/features')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => file.readAsStringSync().contains('screens/auth/'))
        .map((file) => file.path.replaceAll('\\', '/'))
        .toList();

    expect(
      legacyImports,
      isEmpty,
      reason: 'Features must use canonical auth screens: $legacyImports',
    );
  });

  test('legacy shell, splash, and utility facades stay retired', () {
    const retiredPaths = [
      'lib/screens/main_screen.dart',
      'lib/screens/splash_screen.dart',
      'lib/utils/app_theme.dart',
      'lib/utils/constants.dart',
    ];

    for (final path in retiredPaths) {
      expect(
        File(path).existsSync(),
        isFalse,
        reason: 'Retired facade must stay deleted: $path',
      );
    }

    expect(File('lib/core/theme/app_theme.dart').existsSync(), isTrue);
    expect(File('lib/core/config/app_constants.dart').existsSync(), isTrue);
  });

  test('retired customer screens stay deleted and unreferenced', () {
    const retiredPaths = <String>{
      'lib/screens/home/home_screen.dart',
      'lib/screens/home/network_detail_screen.dart',
      'lib/screens/home/purchase_success_screen.dart',
      'lib/screens/wallet/wallet_screen.dart',
      'lib/screens/wallet/deposit_screen.dart',
      'lib/screens/purchases/purchases_screen.dart',
      'lib/screens/profile/profile_screen.dart',
    };
    final inboundImports = <String>[];

    for (final path in retiredPaths) {
      expect(
        File(path).existsSync(),
        isFalse,
        reason: '$path must stay deleted',
      );
    }

    final projectFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    for (final importer in projectFiles) {
      final importerPath = importer.path.replaceAll('\\', '/');
      if (retiredPaths.contains(importerPath)) continue;

      final source = importer.readAsStringSync();
      final directives = RegExp(
        r'''(?:import|export)\s+['"]([^'"]+)['"]''',
      );
      for (final match in directives.allMatches(source)) {
        final dependency = _resolveProjectDependency(
          importerPath,
          match.group(1)!,
        );
        if (dependency != null && retiredPaths.contains(dependency)) {
          inboundImports.add('$importerPath -> $dependency');
        }
      }
    }

    expect(
      inboundImports,
      isEmpty,
      reason: 'Retired screens must remain unreachable: $inboundImports',
    );
  });

  test('legacy provider facade stays retired and unreferenced', () {
    expect(File('lib/providers/app_providers.dart').existsSync(), isFalse);

    final imports = Directory('.')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where(
          (file) =>
              !file.path.replaceAll('\\', '/').endsWith(
                    'test/architecture/customer_entrypoint_dependency_test.dart',
                  ) &&
              file.readAsStringSync().contains('providers/app_providers.dart'),
        )
        .map((file) => file.path.replaceAll('\\', '/'))
        .toList();

    expect(
      imports,
      isEmpty,
      reason: 'Code must import provider owners directly: $imports',
    );
  });

  test('customer authentication boundary is owned by auth feature', () {
    final source = File(
      'lib/features/auth/data/customer_auth_repository.dart',
    ).readAsStringSync();

    expect(source, contains('abstract interface class CustomerAuthRepository'));
    expect(source, contains('class SupabaseCustomerAuthRepository'));
    expect(source, contains('signInWithPhonePassword'));
    expect(File('lib/services/supabase_service.dart').existsSync(), isFalse);
    expect(
      File('lib/core/providers/supabase_service_provider.dart').existsSync(),
      isFalse,
    );
  });

  test('legacy root provider and service layers stay retired', () {
    final legacyFiles = ['lib/providers', 'lib/services']
        .where((path) => Directory(path).existsSync())
        .expand(
          (path) => Directory(path)
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => file.path.endsWith('.dart')),
        )
        .map((file) => file.path.replaceAll('\\', '/'))
        .toList();

    expect(legacyFiles, isEmpty, reason: 'Legacy files: $legacyFiles');
  });

  test('superseded customer models stay removed from the legacy layer', () {
    const removedModels = <String>{
      'lib/models/network_model.dart',
      'lib/models/card_model.dart',
      'lib/models/user_model.dart',
    };

    for (final path in removedModels) {
      expect(
        File(path).existsSync(),
        isFalse,
        reason: '$path was replaced by a feature-owned domain entity',
      );
    }

    final legacyModelFiles = Directory('lib/models').existsSync()
        ? Directory('lib/models')
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))
            .toList()
        : const <File>[];
    expect(legacyModelFiles, isEmpty);
  });
}

String? _resolveProjectDependency(String importerPath, String uri) {
  if (uri.startsWith('package:netyemen/')) {
    return 'lib/${uri.substring('package:netyemen/'.length)}';
  }
  if (uri.startsWith('dart:') || uri.startsWith('package:')) return null;

  final importerUri = File(importerPath).absolute.uri;
  final resolvedFile = File.fromUri(importerUri.resolve(uri));
  final projectRoot = Directory.current.absolute.path;
  final absolutePath = resolvedFile.absolute.path;
  if (!absolutePath.startsWith('$projectRoot${Platform.pathSeparator}')) {
    return null;
  }

  return absolutePath.substring(projectRoot.length + 1);
}
