import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/features/network_discovery/data/supabase_network_catalog_repository.dart';

void main() {
  group('SupabaseNetworkCatalogRepository.chunkIds', () {
    test('keeps every id exactly once and in order', () {
      final ids = List<String>.generate(250, (index) => 'net-$index');

      final chunks = SupabaseNetworkCatalogRepository.chunkIds(ids, 100);

      expect(chunks.map((chunk) => chunk.length), [100, 100, 50]);
      expect(chunks.expand((chunk) => chunk).toList(), ids);
    });

    test('handles empty and exact-multiple inputs', () {
      expect(SupabaseNetworkCatalogRepository.chunkIds(const [], 100), isEmpty);

      final ids = List<String>.generate(200, (index) => 'net-$index');
      final chunks = SupabaseNetworkCatalogRepository.chunkIds(ids, 100);
      expect(chunks, hasLength(2));
      expect(chunks.every((chunk) => chunk.length == 100), isTrue);
    });
  });
}
