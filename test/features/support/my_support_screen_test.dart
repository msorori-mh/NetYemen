import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/features/support/data/fake_support_repository.dart';
import 'package:netyemen/features/support/domain/entities.dart';
import 'package:netyemen/features/support/presentation/support_providers.dart';
import 'package:netyemen/features/support/presentation/support_screens.dart';

void main() {
  testWidgets('Arabic empty state and create action render', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          supportRepositoryProvider.overrideWithValue(FakeSupportRepository()),
        ],
        child: const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: MySupportScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('دعمي'), findsOneWidget);
    expect(find.text('لا توجد تذاكر دعم بعد'), findsOneWidget);
    expect(find.text('تذكرة جديدة'), findsOneWidget);
  });

  testWidgets('offline support list exposes a safe retry action', (
    tester,
  ) async {
    final repository = _OfflineSupportRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          supportRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: MySupportScreen()),
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
}

class _OfflineSupportRepository extends FakeSupportRepository {
  int fetchCalls = 0;

  @override
  Future<List<SupportCase>> fetchCases() async {
    fetchCalls++;
    throw const SocketException('network is unreachable');
  }
}
