import '../domain/entities.dart';

abstract class NetworkCatalogRepository {
  Future<List<NetworkEntity>> fetchApprovedNetworks();
  Future<NetworkEntity?> fetchNetworkDetail(String networkId);
}
