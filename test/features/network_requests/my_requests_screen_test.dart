import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/core/config/app_config.dart';
import 'package:netyemen/features/network_requests/data/fake_network_request_repository.dart';
import 'package:netyemen/features/network_requests/domain/entities.dart';
import 'package:netyemen/features/network_requests/presentation/my_requests_screen.dart';
import 'package:netyemen/features/network_requests/presentation/network_request_providers.dart';
import 'package:netyemen/providers/app_providers.dart';

void main() {
  testWidgets('offline request history uses the shared retry state', (
    tester,
  ) async {
    final repository = _OfflineNetworkRequestRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(AppConfig.demo),
          networkRequestRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: MyRequestsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('customer-offline-state')), findsOneWidget);
    expect(find.text('لا يوجد اتصال بالإنترنت'), findsOneWidget);
    expect(repository.fetchCalls, 1);

    await tester.tap(find.byKey(const Key('customer-load-retry')));
    await tester.pumpAndSettle();
    expect(repository.fetchCalls, 2);
  });

  testWidgets('cancel failure never exposes backend details', (tester) async {
    final repository = _CancelFailingNetworkRequestRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(AppConfig.demo),
          networkRequestRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: MyRequestsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('إلغاء الطلب'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'تعذر إلغاء الطلب. تحقق من الاتصال وحالة الطلب ثم أعد المحاولة.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('DATABASE_SECRET_ERROR'), findsNothing);
  });
}

class _OfflineNetworkRequestRepository extends FakeNetworkRequestRepository {
  int fetchCalls = 0;

  @override
  Future<List<NetworkAdditionRequest>> fetchMyRequests() async {
    fetchCalls++;
    throw const SocketException('network is unreachable');
  }
}

class _CancelFailingNetworkRequestRepository
    extends FakeNetworkRequestRepository {
  _CancelFailingNetworkRequestRepository()
      : super(
          requests: [
            NetworkAdditionRequest(
              id: 'request-1',
              status: 'submitted',
              observedSsidDisplay: 'Wasel WiFi',
              createdAt: DateTime(2026, 9, 19),
            ),
          ],
        );

  @override
  Future<NetworkAdditionRequest> cancelRequest(String requestId) async {
    throw StateError('DATABASE_SECRET_ERROR');
  }
}
