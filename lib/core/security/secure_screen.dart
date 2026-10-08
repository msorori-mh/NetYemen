import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Blocks screenshots, screen recording and the recent-apps preview while a
/// secret (card PIN, access credential) is visible.
///
/// Implemented by `MainActivity` on Android through `FLAG_SECURE`. On every
/// other platform, and in tests without a mocked channel, it is a no-op.
class SecureScreen {
  SecureScreen._();

  static const MethodChannel channel = MethodChannel(
    'com.waselnet.app/secure_screen',
  );

  /// Number of visible widgets that currently need protection. The flag is
  /// only cleared when the last one goes away, so overlapping secret screens
  /// cannot unprotect each other.
  static int _holders = 0;

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Requests protection. Balanced by one [release].
  static Future<void> acquire() async {
    _holders++;
    if (_holders == 1) await _invoke('enable');
  }

  /// Gives up one protection request.
  static Future<void> release() async {
    if (_holders == 0) return;
    _holders--;
    if (_holders == 0) await _invoke('disable');
  }

  static Future<void> _invoke(String method) async {
    if (!_supported) return;
    try {
      await channel.invokeMethod<void>(method);
    } on MissingPluginException {
      // No native handler (tests, or an embedding without MainActivity).
    } on PlatformException {
      // Best effort: never break the screen that shows the secret.
    }
  }

  @visibleForTesting
  static void debugReset() => _holders = 0;
}

/// Keeps the screen protected for as long as this widget is mounted and
/// [enabled] is true.
class SecureScreenScope extends StatefulWidget {
  const SecureScreenScope({
    super.key,
    required this.child,
    this.enabled = true,
  });

  final Widget child;

  /// When false the scope does nothing; flipping it acquires or releases.
  final bool enabled;

  @override
  State<SecureScreenScope> createState() => _SecureScreenScopeState();
}

class _SecureScreenScopeState extends State<SecureScreenScope> {
  bool _held = false;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(SecureScreenScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) _sync();
  }

  void _sync() {
    if (widget.enabled && !_held) {
      _held = true;
      unawaited(SecureScreen.acquire());
    } else if (!widget.enabled && _held) {
      _held = false;
      unawaited(SecureScreen.release());
    }
  }

  @override
  void dispose() {
    if (_held) {
      _held = false;
      unawaited(SecureScreen.release());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
