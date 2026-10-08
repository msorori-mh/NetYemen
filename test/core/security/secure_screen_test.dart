import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/core/security/secure_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<String> calls;

  setUp(() {
    calls = <String>[];
    SecureScreen.debugReset();
    messenger.setMockMethodCallHandler(SecureScreen.channel, (call) async {
      calls.add(call.method);
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(SecureScreen.channel, null);
    SecureScreen.debugReset();
  });

  testWidgets('enables protection while mounted and disables on dispose', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: SecureScreenScope(child: Text('secret'))),
    );
    await tester.pump();
    expect(calls, ['enable']);

    await tester.pumpWidget(const MaterialApp(home: Text('safe')));
    await tester.pump();
    expect(calls, ['enable', 'disable']);
  });

  testWidgets('does nothing while disabled and follows the enabled flag', (
    tester,
  ) async {
    Widget build({required bool enabled}) {
      return MaterialApp(
        home: SecureScreenScope(enabled: enabled, child: const Text('value')),
      );
    }

    await tester.pumpWidget(build(enabled: false));
    await tester.pump();
    expect(calls, isEmpty);

    await tester.pumpWidget(build(enabled: true));
    await tester.pump();
    expect(calls, ['enable']);

    await tester.pumpWidget(build(enabled: false));
    await tester.pump();
    expect(calls, ['enable', 'disable']);
  });

  testWidgets('overlapping scopes keep protection until the last one leaves', (
    tester,
  ) async {
    Widget build({required bool showSecond}) {
      return MaterialApp(
        home: Column(
          children: [
            const SecureScreenScope(child: Text('first')),
            if (showSecond) const SecureScreenScope(child: Text('second')),
          ],
        ),
      );
    }

    await tester.pumpWidget(build(showSecond: true));
    await tester.pump();
    expect(calls, ['enable']);

    await tester.pumpWidget(build(showSecond: false));
    await tester.pump();
    expect(calls, ['enable'], reason: 'the first scope is still visible');

    await tester.pumpWidget(const MaterialApp(home: Text('safe')));
    await tester.pump();
    expect(calls, ['enable', 'disable']);
  });

  test('a missing native handler is ignored', () async {
    messenger.setMockMethodCallHandler(SecureScreen.channel, (call) async {
      calls.add(call.method);
      throw MissingPluginException();
    });

    await SecureScreen.acquire();
    await SecureScreen.release();

    expect(calls, ['enable', 'disable']);
  });
}
