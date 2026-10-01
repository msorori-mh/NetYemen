import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/core/error/app_exceptions.dart';
import 'package:netyemen/core/widgets/customer_load_error.dart';

void main() {
  group('CustomerErrorPresentation', () {
    test('classifies timeout and network failures as offline', () {
      expect(
        CustomerErrorPresentation.from(
          TimeoutException('request timed out'),
          fallbackTitle: 'فشل التحميل',
        ).isOffline,
        isTrue,
      );
      expect(
        CustomerErrorPresentation.from(
          const NetworkException('failed host lookup'),
          fallbackTitle: 'فشل التحميل',
        ).isOffline,
        isTrue,
      );
    });

    test('keeps non-connectivity failures generic', () {
      final state = CustomerErrorPresentation.from(
        StateError('DATABASE_SECRET_ERROR'),
        fallbackTitle: 'تعذر تحميل البيانات',
      );

      expect(state.isOffline, isFalse);
      expect(state.title, 'تعذر تحميل البيانات');
      expect(state.message, isNot(contains('DATABASE_SECRET_ERROR')));
    });
  });

  testWidgets('offline state is actionable and does not expose errors', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomerLoadError(
            error: TimeoutException('INTERNAL_ENDPOINT_SECRET'),
            fallbackTitle: 'تعذر تحميل البيانات',
            onRetry: () => retries++,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('customer-offline-state')), findsOneWidget);
    expect(find.text('لا يوجد اتصال بالإنترنت'), findsOneWidget);
    expect(find.textContaining('INTERNAL_ENDPOINT_SECRET'), findsNothing);

    await tester.tap(find.byKey(const Key('customer-load-retry')));
    expect(retries, 1);
  });
}
