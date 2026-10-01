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
    expect(find.text('الدعم والشكاوى'), findsOneWidget);
    expect(find.text('لا توجد تذاكر دعم بعد'), findsOneWidget);
    expect(find.text('تذكرة جديدة'), findsOneWidget);

    await tester.tap(find.text('تذكرة جديدة'));
    await tester.pumpAndSettle();

    expect(find.text('الخدمة'), findsOneWidget);
    expect(find.text('عادية'), findsOneWidget);
    expect(find.textContaining('معرّف الشبكة'), findsNothing);
    expect(find.textContaining('معرّف الباقة'), findsNothing);
  });

  testWidgets('customer support list and details hide operational codes', (
    tester,
  ) async {
    final repository = FakeSupportRepository()
      ..cases.add(
        SupportCase(
          id: 'case-1',
          number: 1001,
          type: SupportCaseType.ticket,
          category: 'service',
          priority: 'normal',
          subject: 'ضعف الاتصال',
          description: 'الخدمة بطيئة منذ الصباح',
          status: 'waiting_customer',
          dueAt: DateTime.now().add(const Duration(hours: 2)),
          createdAt: DateTime.now(),
        ),
      );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [supportRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: MySupportScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('بانتظار ردك'), findsOneWidget);
    expect(find.textContaining('الأولوية: عادية'), findsOneWidget);
    expect(find.textContaining('waiting_customer'), findsNothing);
    expect(find.textContaining('normal'), findsNothing);

    await tester.tap(find.text('ضعف الاتصال'));
    await tester.pumpAndSettle();

    expect(find.text('لا توجد رسائل بعد. أرسل ردًا لإضافة معلومات جديدة.'),
        findsOneWidget);
    expect(find.text('السجل التشغيلي'), findsNothing);
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
