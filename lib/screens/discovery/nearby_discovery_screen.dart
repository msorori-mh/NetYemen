// lib/screens/discovery/nearby_discovery_screen.dart
//
// BR-NETWORK-011: scanning MUST be explicitly triggered by a user button tap
// — never silent, continuous, or background. This screen never scans in
// initState; only _startScan() (wired to a button press) ever calls
// WiFiScan. Matching against our own registered SSID catalog happens
// entirely on-device: the scanned SSID list is never sent to the backend,
// only the (already-public) catalog is fetched from it. Hardware BSSIDs are
// never read from WiFiAccessPoint at all in this file, even though the
// plugin exposes them — only `.ssid`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_scan/wifi_scan.dart';

import '../../providers/app_providers.dart';
import '../../utils/app_theme.dart';
import '../home/network_detail_screen.dart';
import 'suggest_network_screen.dart';

typedef _SsidMatch = ({String ssid, String networkId, String networkName});

class NearbyDiscoveryScreen extends ConsumerStatefulWidget {
  const NearbyDiscoveryScreen({super.key});

  @override
  ConsumerState<NearbyDiscoveryScreen> createState() =>
      _NearbyDiscoveryScreenState();
}

enum _ScanUiState { idle, scanning, matched, empty, permissionDenied, error }

class _NearbyDiscoveryScreenState extends ConsumerState<NearbyDiscoveryScreen> {
  _ScanUiState _state = _ScanUiState.idle;
  List<_SsidMatch> _matches = [];
  bool _permissionPermanentlyDenied = false;
  String? _errorMessage;

  Future<void> _startScan() async {
    setState(() {
      _state = _ScanUiState.scanning;
      _errorMessage = null;
    });

    final permission = await Permission.location.request();
    if (!permission.isGranted) {
      setState(() {
        _state = _ScanUiState.permissionDenied;
        _permissionPermanentlyDenied = permission.isPermanentlyDenied;
      });
      return;
    }

    final canStart = await WiFiScan.instance.canStartScan();
    if (canStart != CanStartScan.yes) {
      setState(() {
        _state = _ScanUiState.error;
        _errorMessage = _friendlyCanStartMessage(canStart);
      });
      return;
    }

    await WiFiScan.instance.startScan();
    // The platform scan is asynchronous; a short wait is the simplest way to
    // let it settle before reading results back (matches the plugin's own
    // recommended usage pattern).
    await Future.delayed(const Duration(seconds: 2));

    final canGet = await WiFiScan.instance.canGetScannedResults();
    if (canGet != CanGetScannedResults.yes) {
      setState(() {
        _state = _ScanUiState.error;
        _errorMessage = 'تعذّر قراءة نتائج المسح';
      });
      return;
    }

    final results = await WiFiScan.instance.getScannedResults();
    final scannedSsids = results
        .map((ap) => ap.ssid)
        .where((ssid) => ssid.isNotEmpty)
        .toSet();

    if (!mounted) return;

    try {
      final service = ref.read(supabaseServiceProvider);
      final catalog = await service.getNetworkSsidCatalog();

      final seenNetworkIds = <String>{};
      final matches = <_SsidMatch>[];
      for (final entry in catalog) {
        if (scannedSsids.contains(entry.ssid) &&
            seenNetworkIds.add(entry.networkId)) {
          matches.add(entry);
        }
      }

      setState(() {
        _matches = matches;
        _state = matches.isEmpty ? _ScanUiState.empty : _ScanUiState.matched;
      });
    } catch (e) {
      setState(() {
        _state = _ScanUiState.error;
        _errorMessage = 'تعذّر تحميل قائمة الشبكات المسجّلة';
      });
    }
  }

  String _friendlyCanStartMessage(CanStartScan can) {
    switch (can) {
      case CanStartScan.noLocationServiceDisabled:
        return 'يرجى تفعيل خدمة الموقع لإجراء المسح';
      case CanStartScan.notSupported:
        return 'جهازك لا يدعم مسح شبكات الواي فاي';
      default:
        return 'تعذّر بدء المسح، حاول مرة أخرى';
    }
  }

  Future<void> _openNetwork(_SsidMatch match) async {
    final service = ref.read(supabaseServiceProvider);
    final network = await service.getNetworkById(match.networkId);
    if (network == null || !mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NetworkDetailScreen(network: network)),
    );
  }

  void _openSuggestNetwork() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SuggestNetworkScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الشبكات القريبة')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.wifi_find_rounded, size: 64, color: AppTheme.primary),
            const SizedBox(height: 16),
            const Text(
              'امسح الشبكات القريبة',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'يتم إجراء المسح على جهازك فقط، ولا تُرسل نتائج المسح إلى الخادم أبداً',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 54,
              child: ElevatedButton.icon(
                onPressed:
                    _state == _ScanUiState.scanning ? null : _startScan,
                icon: _state == _ScanUiState.scanning
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.search),
                label: Text(
                  _state == _ScanUiState.scanning ? 'جارٍ المسح...' : 'امسح الآن',
                ),
              ),
            ),
            const SizedBox(height: 24),
            Expanded(child: _buildResultArea()),
          ],
        ),
      ),
    );
  }

  Widget _buildResultArea() {
    switch (_state) {
      case _ScanUiState.idle:
      case _ScanUiState.scanning:
        return const SizedBox.shrink();

      case _ScanUiState.permissionDenied:
        return _InfoPanel(
          icon: Icons.location_off_outlined,
          color: AppTheme.warning,
          message: _permissionPermanentlyDenied
              ? 'إذن الموقع مرفوض بشكل دائم. افتح الإعدادات لتفعيله يدوياً'
              : 'يحتاج المسح إلى إذن الموقع للعثور على الشبكات القريبة',
          actionLabel: _permissionPermanentlyDenied ? 'فتح الإعدادات' : 'حاول مجدداً',
          onAction: _permissionPermanentlyDenied ? openAppSettings : _startScan,
        );

      case _ScanUiState.error:
        return _InfoPanel(
          icon: Icons.error_outline,
          color: AppTheme.error,
          message: _errorMessage ?? 'حدث خطأ غير متوقع',
          actionLabel: 'حاول مجدداً',
          onAction: _startScan,
        );

      case _ScanUiState.empty:
        return _InfoPanel(
          icon: Icons.wifi_off_rounded,
          color: AppTheme.textMuted,
          message: 'لم يتم العثور على شبكة NetYemen قريبة منك',
          actionLabel: 'اقترح شبكة جديدة',
          onAction: _openSuggestNetwork,
        );

      case _ScanUiState.matched:
        return ListView.builder(
          itemCount: _matches.length,
          itemBuilder: (context, index) {
            final match = _matches[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppTheme.accent,
                  child: Icon(Icons.wifi_rounded, color: Colors.white),
                ),
                title: Text('قريب منك: ${match.networkName}'),
                subtitle: Text(match.ssid),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => _openNetwork(match),
              ),
            );
          },
        );
    }
  }
}

class _InfoPanel extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  const _InfoPanel({
    required this.icon,
    required this.color,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: color),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}
