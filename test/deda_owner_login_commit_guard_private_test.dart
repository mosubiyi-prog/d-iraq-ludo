import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:d_iraq_ludo/main.dart' as deda;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('verified canonical login cannot persist a claimed UID without Auth',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await expectLater(
      deda.DedaPreferences.saveLogin(
        name: 'Original Owner',
        normalizedPhone: '+9647712345678',
        type: deda.DedaAccountType.user,
        verifiedCanonicalProfile: true,
        verifiedOriginalUid: 'unproven-owner-uid',
      ),
      throwsStateError,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('deda_logged_in_v1'), isNull);
    expect(prefs.getString('deda_step2_linked_verified_uid_v1'), isNull);
    expect(deda.DedaPreferences.isLoggedIn, false);
  });

  test('verified canonical login rejects missing UID even if pilot is off',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await expectLater(
      deda.DedaPreferences.saveLogin(
        name: 'Original Owner',
        normalizedPhone: '+9647712345678',
        type: deda.DedaAccountType.user,
        verifiedCanonicalProfile: true,
      ),
      throwsStateError,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('deda_logged_in_v1'), isNull);
  });
}
