import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/pin_repository.dart';

final pinRepositoryProvider = Provider<PinRepository>((ref) {
  return SupabasePinRepository();
});
