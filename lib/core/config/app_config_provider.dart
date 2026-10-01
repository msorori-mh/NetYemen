import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_config.dart';

/// Application configuration belongs to the shared bootstrap layer.
///
/// Keeping this provider in [core] prevents unrelated features from depending
/// on network discovery just to learn whether the app is configured or in
/// demo mode.
final appConfigProvider = Provider<AppConfig>((ref) {
  return AppConfig.fromEnvironment();
});
