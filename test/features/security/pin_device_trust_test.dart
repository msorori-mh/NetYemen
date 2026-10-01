import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/features/security/data/pin_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('clearPinDeviceTrust forgets every trusted account on the device',
      () async {
    SharedPreferences.setMockInitialValues({
      'pin_trusted_user-a': '1',
      'pin_trusted_user-b': '1',
      'unrelated_setting': 'kept',
    });

    await clearPinDeviceTrust();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), {'unrelated_setting'});
  });
}
