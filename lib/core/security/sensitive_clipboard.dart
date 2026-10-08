import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Copies a secret (card PIN, access credential) and wipes it from the
/// clipboard after [clearAfter].
///
/// The service is owned by the app's provider scope, not by a screen, so the
/// wipe still happens when the customer leaves the screen right after
/// copying. The clipboard is only cleared when it still holds the copied
/// value; anything the customer copied afterwards is left alone.
class SensitiveClipboard {
  SensitiveClipboard({this.clearAfter = const Duration(seconds: 60)});

  final Duration clearAfter;

  Timer? _timer;

  /// Copies [text] and schedules its removal.
  Future<void> copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    _timer?.cancel();
    _timer = Timer(clearAfter, () => unawaited(_clearIfUnchanged(text)));
  }

  Future<void> _clearIfUnchanged(String text) async {
    _timer = null;
    try {
      final current = await Clipboard.getData(Clipboard.kTextPlain);
      if (current?.text == text) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
    } catch (_) {
      // Best effort: the platform may refuse clipboard access in background.
    }
  }

  /// Cancels a pending wipe. Called when the provider scope is torn down.
  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}

final sensitiveClipboardProvider = Provider<SensitiveClipboard>((ref) {
  final clipboard = SensitiveClipboard();
  ref.onDispose(clipboard.dispose);
  return clipboard;
});
