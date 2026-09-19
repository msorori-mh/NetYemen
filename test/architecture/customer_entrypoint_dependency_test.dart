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
