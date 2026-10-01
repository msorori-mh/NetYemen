import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netyemen/main.dart';

void main() {
  group('NetYemenApp', () {
    testWidgets('provides Arabic localizations and right-to-left layout',
        (WidgetTester tester) async {
      late BuildContext captured;

      await tester.pumpWidget(
        ProviderScope(
          child: NetYemenApp(
            home: Builder(
              builder: (context) {
                captured = context;
                return Scaffold(
                  appBar: AppBar(title: const Text('NetYemen')),
                  body: const TextField(),
                  bottomNavigationBar: BottomNavigationBar(
                    items: const [
                      BottomNavigationBarItem(
                        icon: Icon(Icons.wifi_rounded),
                        label: 'الشبكات',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.person_outline),
                        label: 'حسابي',
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );

      // AppBar, TextField and BottomNavigationBar all require
      // MaterialLocalizations; without the Arabic delegates they throw.
      expect(tester.takeException(), isNull);
      expect(find.text('NetYemen'), findsOneWidget);
      expect(Localizations.localeOf(captured).languageCode, 'ar');
      expect(Directionality.of(captured), TextDirection.rtl);
    });
  });
}
