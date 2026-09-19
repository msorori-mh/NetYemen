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

    final legacyFacade =
        File('lib/providers/app_providers.dart').readAsStringSync();
    expect(legacyFacade, isNot(contains('final authStateProvider =')));
    expect(legacyFacade, isNot(contains('final currentUserProvider =')));
    expect(legacyFacade, isNot(contains('final currentUserRolesProvider =')));

    final remainingFeatureImports = Directory('lib/features')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where(
          (file) => file
              .readAsStringSync()
              .contains("providers/app_providers.dart'"),
        )
        .map((file) => file.path.replaceAll('\\', '/'))
        .toList();

    expect(
      remainingFeatureImports,
      equals(['lib/features/profile/presentation/profile_screen.dart']),
      reason: 'Features must depend on owned providers, not the legacy facade.',
    );
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
