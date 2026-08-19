/// Parses WASEL NET deep-link routes used by notifications.
///
/// Supported forms:
/// - `waselnet://network/{id}`
/// - `waselnet://package/{id}`
/// - `waselnet://request/{id}`
/// - `waselnet://notifications`
/// - `waselnet://profile`
/// - legacy compatibility: `netyemen://...`
/// - bare paths: `network/{id}`, `package/{id}`, ...
class DeepLinkTarget {
  final DeepLinkKind kind;
  final String? id;

  const DeepLinkTarget(this.kind, {this.id});
}

enum DeepLinkKind { network, package, request, notifications, profile, unknown }

class DeepLinkParser {
  const DeepLinkParser();

  DeepLinkTarget parse(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const DeepLinkTarget(DeepLinkKind.unknown);
    }

    var value = raw.trim();
    if (value.startsWith('waselnet://')) {
      value = value.substring('waselnet://'.length);
    } else if (value.startsWith('netyemen://')) {
      // V1 transition compatibility for legacy links.
      value = value.substring('netyemen://'.length);
    }
    if (value.startsWith('/')) {
      value = value.substring(1);
    }

    final parts = value.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) {
      return const DeepLinkTarget(DeepLinkKind.unknown);
    }

    switch (parts.first) {
      case 'network':
        return DeepLinkTarget(
          DeepLinkKind.network,
          id: parts.length > 1 ? parts[1] : null,
        );
      case 'package':
        return DeepLinkTarget(
          DeepLinkKind.package,
          id: parts.length > 1 ? parts[1] : null,
        );
      case 'request':
        return DeepLinkTarget(
          DeepLinkKind.request,
          id: parts.length > 1 ? parts[1] : null,
        );
      case 'notifications':
      case 'notification-center':
        return const DeepLinkTarget(DeepLinkKind.notifications);
      case 'profile':
        return const DeepLinkTarget(DeepLinkKind.profile);
      default:
        return const DeepLinkTarget(DeepLinkKind.unknown);
    }
  }
}
