import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/app/demo_data_ribbon.dart';
import 'package:netyemen/core/config/app_config.dart';
import 'package:netyemen/core/config/app_config_provider.dart';

Widget _app(AppConfig config) {
  return ProviderScope(
    overrides: [appConfigProvider.overrideWithValue(config)],
    child: MaterialApp(
      home: const Scaffold(body: Text('screen')),
      builder: (context, child) => DemoDataRibbon(child: child!),
    ),
  );
}

void main() {
  testWidgets('marks every screen while demo data is in use', (tester) async {
    await tester.pumpWidget(_app(AppConfig.demo));

    expect(find.byKey(const Key('demo-data-ribbon')), findsOneWidget);
    expect(find.text('screen'), findsOneWidget);
  });

  testWidgets('is absent for a build bound to a real backend', (tester) async {
    await tester.pumpWidget(
      _app(
        const AppConfig(
          supabaseUrl: 'https://example.supabase.co',
          supabasePublishableKey: 'anon-key',
        ),
      ),
    );

    expect(find.byKey(const Key('demo-data-ribbon')), findsNothing);
    expect(find.text('screen'), findsOneWidget);
  });
}
