import '../domain/entities.dart';
import 'network_catalog_repository.dart';

class DemoNetworkCatalogRepository implements NetworkCatalogRepository {
  static const _demoNetworks = [
    NetworkEntity(
      id: 'demo-net-1',
      commercialName: 'شبكة يمن نت',
      governorate: 'أمانة العاصمة',
      city: 'صنعاء',
      district: 'الوحدة',
      ssidAliases: [
        SsidAlias(
          id: 'alias-1a',
          networkId: 'demo-net-1',
          ssidDisplay: 'YemenNet_Fast',
          ssidNormalized: 'yemennet-fast',
        ),
        SsidAlias(
          id: 'alias-1b',
          networkId: 'demo-net-1',
          ssidDisplay: 'YemenNet-5G',
          ssidNormalized: 'yemennet-5g',
        ),
      ],
    ),
    NetworkEntity(
      id: 'demo-net-2',
      commercialName: 'شبكة عدن للاتصالات',
      governorate: 'عدن',
      city: 'كريتر',
      district: 'المعلا',
      ssidAliases: [
        SsidAlias(
          id: 'alias-2a',
          networkId: 'demo-net-2',
          ssidDisplay: 'AdenConnect',
          ssidNormalized: 'adenconnect',
        ),
      ],
    ),
    NetworkEntity(
      id: 'demo-net-3',
      commercialName: 'شبكة تعز السريعة',
      governorate: 'تعز',
      city: 'تعز',
      ssidAliases: [
        SsidAlias(
          id: 'alias-3a',
          networkId: 'demo-net-3',
          ssidDisplay: 'TaizWiFi',
          ssidNormalized: 'taizwifi',
        ),
      ],
    ),
  ];

  @override
  Future<List<NetworkEntity>> fetchApprovedNetworks() async {
    await Future.delayed(const Duration(milliseconds: 300));
    return List.of(_demoNetworks);
  }

  @override
  Future<NetworkEntity?> fetchNetworkDetail(String networkId) async {
    await Future.delayed(const Duration(milliseconds: 200));
    try {
      return _demoNetworks.firstWhere((n) => n.id == networkId);
    } catch (_) {
      return null;
    }
  }
}
