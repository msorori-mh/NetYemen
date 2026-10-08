import 'package:unorm_dart/unorm_dart.dart';

final RegExp _whitespaceRun = RegExp(r'\s+');

/// Normalises free text for the customer network search.
///
/// Applied to BOTH the typed query and the searched fields, so they are
/// always compared in the same form: trimmed, Unicode NFC, lower-cased, and
/// with every run of whitespace collapsed to one space. Unlike SSID matching
/// it keeps spaces, so a multi-word query such as «شبكة عدن» still matches a
/// commercial name that contains those words.
String normalizeForSearch(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '';
  return nfc(trimmed).toLowerCase().replaceAll(_whitespaceRun, ' ');
}
