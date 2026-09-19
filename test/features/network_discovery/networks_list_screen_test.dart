import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/features/network_discovery/data/demo_network_catalog_repository.dart';
import 'package:netyemen/features/network_discovery/presentation/network_discovery_providers.dart';
import 'package:netyemen/features/network_discovery/presentation/networks_list_screen.dart';

void main() {
  testWidgets('filters networks by search and governorate', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          networkCatalogRepositoryProvider.overrideWithValue(
            DemoNetworkCatalogRepository(),
          ),
        ],
        child: const MaterialApp(home: NetworksListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('شبكة يمن نت'), findsOneWidget);
    expect(find.text('شبكة عدن للاتصالات'), findsOneWidget);
    expect(find.text('شبكة تعز السريعة'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('network-search-field')),
      'عدن',
    );
    await tester.pump();

    expect(find.text('شبكة عدن للاتصالات'), findsOneWidget);
    expect(find.text('شبكة يمن نت'), findsNothing);

    await tester.tap(find.byKey(const Key('network-search-clear')));
    await tester.pump();
    final searchField = tester.widget<TextField>(
      find.byKey(const Key('network-search-field')),
    );
    expect(searchField.controller?.text, isEmpty);
    expect(find.text('شبكة يمن نت'), findsOneWidget);

    await tester.tap(find.byKey(const Key('network-governorate-تعز')));
    await tester.pump();
    expect(find.text('شبكة تعز السريعة'), findsOneWidget);
    expect(find.text('شبكة عدن للاتصالات'), findsNothing);

    await tester.enterText(
      find.byKey(const Key('network-search-field')),
      'صنعاء',
    );
    await tester.pump();
    expect(find.text('لا توجد نتائج مطابقة لبحثك'), findsOneWidget);

    await tester.tap(find.byKey(const Key('network-filters-clear')));
    await tester.pump();
    expect(find.text('شبكة يمن نت'), findsOneWidget);
    expect(find.text('شبكة عدن للاتصالات'), findsOneWidget);
    expect(find.text('شبكة تعز السريعة'), findsOneWidget);
  });
}
