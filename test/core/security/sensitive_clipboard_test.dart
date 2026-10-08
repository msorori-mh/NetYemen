import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/core/security/sensitive_clipboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String? clipboardText;
  var denyRead = false;

  setUp(() {
    clipboardText = null;
    denyRead = false;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        final arguments = call.arguments as Map<dynamic, dynamic>;
        clipboardText = arguments['text'] as String?;
        return null;
      }
      if (call.method == 'Clipboard.getData') {
        if (denyRead) throw PlatformException(code: 'denied');
        return <String, dynamic>{'text': clipboardText};
      }
      return null;
    });
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('wipes the copied secret after the delay', (tester) async {
    final clipboard = SensitiveClipboard();
    addTearDown(clipboard.dispose);

    await clipboard.copy('CARD-1');
    expect(clipboardText, 'CARD-1');

    await tester.pump(const Duration(seconds: 59));
    expect(clipboardText, 'CARD-1');

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(clipboardText, isEmpty);
  });

  testWidgets('leaves text the customer copied afterwards', (tester) async {
    final clipboard = SensitiveClipboard();
    addTearDown(clipboard.dispose);

    await clipboard.copy('CARD-1');
    clipboardText = 'a phone number';

    await tester.pump(const Duration(seconds: 60));
    await tester.pump();
    expect(clipboardText, 'a phone number');
  });

  testWidgets('still wipes when the clipboard cannot be read', (tester) async {
    final clipboard = SensitiveClipboard();
    addTearDown(clipboard.dispose);

    await clipboard.copy('CARD-1');
    denyRead = true;

    await tester.pump(const Duration(seconds: 60));
    await tester.pump();
    expect(clipboardText, isEmpty);
  });

  testWidgets('a newer copy restarts the delay', (tester) async {
    final clipboard = SensitiveClipboard();
    addTearDown(clipboard.dispose);

    await clipboard.copy('CARD-1');
    await tester.pump(const Duration(seconds: 40));
    await clipboard.copy('CARD-2');

    await tester.pump(const Duration(seconds: 40));
    await tester.pump();
    expect(clipboardText, 'CARD-2');

    await tester.pump(const Duration(seconds: 20));
    await tester.pump();
    expect(clipboardText, isEmpty);
  });

  testWidgets('dispose cancels a pending wipe', (tester) async {
    final clipboard = SensitiveClipboard();

    await clipboard.copy('CARD-1');
    clipboard.dispose();

    await tester.pump(const Duration(seconds: 60));
    await tester.pump();
    expect(clipboardText, 'CARD-1');
  });
}
