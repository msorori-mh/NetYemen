abstract class WifiScanService {
  Future<List<String>> performScan();
  Future<bool> get isSupported;
}
