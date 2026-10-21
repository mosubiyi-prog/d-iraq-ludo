import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:d_iraq_ludo/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('legacy 3 and exact 3 royal frames all free; no wallet used', () {
    for (var style = 0; style < 6; style++) {
      expect(dedaProfileFrameIsFree(style), isTrue,
          reason: 'Royal slot $style must be free to choose and save');
    }
    expect(dedaProfileFrameIsFree(-1), isFalse);
    expect(dedaProfileFrameIsFree(6), isFalse,
        reason: 'Unbundled paid FRAME_03/05..16 must not auto unlock');
  });

  test('all three royal styles 3..5 persist without old index 2 clamp',
      () async {
    SharedPreferences.setMockInitialValues(<String,Object>{});
    DedaPreferences.phone = '07700001122';
    for (final style in <int>[3, 4, 5]) {
      await DedaPreferences.setProfileAppearance(
        avatarStyle: 0, frameStyle: style, backgroundStyle: 0);
      expect(DedaPreferences.profileFrameStyle, style);
      final prefs=await SharedPreferences.getInstance();
      expect(prefs.getInt('deda_profile_frame_v1_07700001122'), style);
    }
    // Existing legacy slot continues to be selectable.
    await DedaPreferences.setProfileAppearance(
      avatarStyle: 0, frameStyle: 2, backgroundStyle: 0);
    expect(DedaPreferences.profileFrameStyle, 2);
  });
}
