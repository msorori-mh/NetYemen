// lib/core/utils/sensitive_clipboard.dart

import 'dart:async';

import 'package:flutter/services.dart';

/// Copies secrets (card numbers, access passwords) to the clipboard and wipes
/// them again after [clearAfter], unless the user has copied something else
/// in the meantime.
class SensitiveClipboard {
  static const defaultClearAfter = Duration(seconds: 60);

  final Duration clearAfter;
  Timer? _timer;
  String? _pending;

  SensitiveClipboard({this.clearAfter = defaultClearAfter});

  /// Whether a copied secret may still be on the clipboard.
  bool get hasPending => _pending != null;

  Future<void> copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    _timer?.cancel();
    _pending = text;
    _timer = Timer(clearAfter, clearNow);
  }

  /// Clears the clipboard now if it still holds the last copied secret.
  Future<void> clearNow() async {
    final text = _pending;
    _timer?.cancel();
    _timer = null;
    _pending = null;
    if (text == null) return;
    try {
      final current = await Clipboard.getData(Clipboard.kTextPlain);
      if (current?.text == text) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
    } catch (_) {
      // Clipboard access is best-effort; never crash a screen over it.
    }
  }

  /// Cancels the timer and clears a still-pending secret immediately, so
  /// leaving a screen early never leaves the secret on the clipboard.
  void dispose() {
    if (_pending != null) {
      unawaited(clearNow());
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }
}
