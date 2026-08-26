import 'dart:math';
import 'dart:typed_data';

/// Generates standards-compliant random UUID v4 strings without adding a
/// third-party dependency.
class UuidGenerator {
  static final _random = Random.secure();

  /// Returns a random UUID v4 string in the canonical 8-4-4-4-12 format.
  static String generateV4() {
    final bytes = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      bytes[i] = _random.nextInt(256);
    }

    // Set version (4) and variant (RFC 4122) bits.
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    final hex = bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .toList(growable: false);

    return '${hex[0]}${hex[1]}${hex[2]}${hex[3]}-'
        '${hex[4]}${hex[5]}-${hex[6]}${hex[7]}-'
        '${hex[8]}${hex[9]}-${hex[10]}${hex[11]}${hex[12]}${hex[13]}${hex[14]}${hex[15]}';
  }
}
