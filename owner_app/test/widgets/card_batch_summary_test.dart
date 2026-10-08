import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owner/utils/card_batch_validator.dart';
import 'package:owner/widgets/card_batch_summary.dart';

Widget _host(Widget child) {
  return MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

void main() {
  testWidgets('the preview never prints duplicate or invalid PINs',
      (tester) async {
    final validation = validateCardBatch(
      '11112222\n33334444\n11112222\n5555 6666',
    );

    await tester.pumpWidget(
      _host(CardBatchValidationSummary(validation: validation)),
    );

    expect(find.textContaining('11112222'), findsNothing);
    expect(find.textContaining('33334444'), findsNothing);
    expect(find.textContaining('5555'), findsNothing);
    // Counts and line numbers are shown instead.
    expect(find.text('كروت صالحة'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.textContaining('أسطر مكررة: 3'), findsOneWidget);
    expect(find.textContaining('مسافات): 4'), findsOneWidget);
  });

  testWidgets('a clean batch shows only the valid count', (tester) async {
    await tester.pumpWidget(
      _host(
        CardBatchValidationSummary(
          validation: validateCardBatch('1111\n2222\n3333'),
        ),
      ),
    );

    expect(find.text('3'), findsOneWidget);
    expect(find.textContaining('أسطر مكررة'), findsNothing);
    expect(find.textContaining('غير صالحة'), findsNothing);
  });

  testWidgets('the server result shows skipped duplicates and replays',
      (tester) async {
    const result = CardBatchUploadResult(
      batchId: 'batch-42',
      ingestedCount: 7,
      duplicatesSkipped: 2,
      replayed: true,
    );

    await tester.pumpWidget(_host(const CardBatchResultCard(result: result)));

    expect(find.text('هذه الدفعة سبق رفعها'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.textContaining('batch-42'), findsOneWidget);
  });

  testWidgets('a first upload is reported as uploaded', (tester) async {
    const result = CardBatchUploadResult(
      batchId: 'batch-1',
      ingestedCount: 5,
      duplicatesSkipped: 0,
      replayed: false,
    );

    await tester.pumpWidget(_host(const CardBatchResultCard(result: result)));

    expect(find.text('تم رفع الدفعة'), findsOneWidget);
    expect(find.text('هذه الدفعة سبق رفعها'), findsNothing);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
  });
}
