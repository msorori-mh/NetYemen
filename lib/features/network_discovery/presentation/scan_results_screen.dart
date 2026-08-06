import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/error/app_exceptions.dart';
import '../../../core/theme/app_theme.dart';
import '../../network_discovery/domain/entities.dart';
import '../../network_discovery/presentation/network_discovery_providers.dart';
import '../../network_requests/presentation/add_request_screen.dart';
import 'network_details_screen.dart';

class ScanResultsScreen extends ConsumerWidget {
  const ScanResultsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scanResult = ref.watch(scanResultProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('نتائج المسح'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(scanNotifierProvider).performScan(),
          ),
        ],
      ),
      body: scanResult == null
          ? const Center(child: CircularProgressIndicator())
          : scanResult.when(
              data: (result) => _ScanResultsBody(result: result),
              error: (e, _) => _ScanErrorState(error: e),
              loading: () => const Center(child: CircularProgressIndicator()),
            ),
    );
  }
}

class _ScanResultsBody extends ConsumerWidget {
  final ScanMatchResult result;
  const _ScanResultsBody({required this.result});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (result.matchedNetworks.isNotEmpty) ...[
          const Text(
            'شبكات مطابقة',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...result.matchedNetworks.map(
            (network) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppTheme.accent.withValues(alpha: 0.1),
                  child: const Icon(Icons.check_circle,
                      color: AppTheme.accent, size: 20),
                ),
                title: Text(network.commercialName),
                subtitle: Text(network.locationText),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => NetworkDetailsScreen(network: network),
                  ),
                ),
              ),
            ),
          ),
        ],
        if (result.unmatchedSsids.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text(
            'شبكات غير معروفة',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...result.unmatchedSsids.map(
            (ssid) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppTheme.warning.withValues(alpha: 0.1),
                  child: const Icon(Icons.help_outline,
                      color: AppTheme.warning, size: 20),
                ),
                title: Text(ssid),
                subtitle: const Text('غير موجودة في القائمة المعتمدة'),
                trailing: TextButton(
                  onPressed: () {
                    ref
                        .read(selectedScanSsidProvider.notifier)
                        .state = ssid;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            const AddRequestScreen(),
                      ),
                    );
                  },
                  child: const Text('طلب إضافة'),
                ),
              ),
            ),
          ),
        ],
        if (result.matchedNetworks.isEmpty &&
            result.unmatchedSsids.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text('لم يتم العثور على شبكات'),
            ),
          ),
      ],
    );
  }
}

class _ScanErrorState extends StatelessWidget {
  final Object error;
  const _ScanErrorState({required this.error});

  @override
  Widget build(BuildContext context) {
    String message;
    IconData icon;

    if (error is ScanPermissionDeniedException) {
      message = 'تم رفض إذن المسح. يرجى تفعيل الأذونات من إعدادات الجهاز.';
      icon = Icons.security;
    } else if (error is ScanUnsupportedException) {
      message = 'المسح غير مدعوم على هذا الجهاز.';
      icon = Icons.device_unknown;
    } else if (error is ScanThrottledException) {
      message = 'تم تقييد المسح بسبب التكرار. حاول بعد قليل.';
      icon = Icons.timer_off;
    } else if (error is WifiDisabledException) {
      message = 'يرجى تفعيل الواي فاي أولاً.';
      icon = Icons.wifi_off;
    } else {
      message = 'حدث خطأ أثناء المسح.';
      icon = Icons.error_outline;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: AppTheme.warning),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
