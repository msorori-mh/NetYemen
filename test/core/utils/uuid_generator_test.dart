import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/core/utils/uuid_generator.dart';

void main() {
  group('UuidGenerator', () {
    final uuidPattern = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );

    test('generateV4 produces a valid lowercase UUID v4 string', () {
      final uuid = UuidGenerator.generateV4();
      expect(uuidPattern.hasMatch(uuid), isTrue, reason: 'generated: $uuid');
    });

    test('generateV4 produces unique values for independent calls', () {
      final values = <String>{};
      for (var i = 0; i < 100; i++) {
        values.add(UuidGenerator.generateV4());
      }
      expect(values.length, 100);
    });

    test('generateV4 sets the RFC 4122 variant bits', () {
      final uuid = UuidGenerator.generateV4();
      final variantChar = uuid[19];
      expect(
        ['8', '9', 'a', 'b'],
        contains(variantChar),
        reason: 'variant nibble should be 8/9/a/b',
      );
    });
  });
}
