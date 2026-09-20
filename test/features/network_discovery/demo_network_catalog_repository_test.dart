import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/features/network_discovery/data/demo_network_catalog_repository.dart';

void main() {
  group('DemoNetworkCatalogRepository', () {
    final repository = DemoNetworkCatalogRepository();

    test('fetchApprovedNetworks returns demo networks', () async {
      final networks = await repository.fetchApprovedNetworks();
      expect(networks, isNotEmpty);
      expect(networks.any((n) => n.commercialName == 'شبكة يمن نت'), isTrue);
    });

    test('fetchNetworkDetail returns matching network', () async {
      final network = await repository.fetchNetworkDetail('demo-net-1');
      expect(network, isNotNull);
      expect(network!.commercialName, 'شبكة يمن نت');
      expect(network.ssidAliases, isNotEmpty);
    });

    test('fetchNetworkDetail returns null for unknown id', () async {
      final network = await repository.fetchNetworkDetail('unknown');
      expect(network, isNull);
    });

    test('network matches search by commercial name, city and ssid', () async {
      final repository = DemoNetworkCatalogRepository();
      final networks = await repository.fetchApprovedNetworks();
      final network = networks.first;
      expect(network.matchesSearch('yemen'), isTrue);
      expect(network.matchesSearch('fast'), isTrue);
      expect(network.matchesSearch('nonexistent'), isFalse);
    });
  });
}
