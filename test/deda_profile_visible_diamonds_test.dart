import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_profile_visible_diamonds.dart';

void main() {
  test('normal user: only rewarded and gifted diamonds displayed', () {
    expect(dedaProfileVisibleDiamonds(
      ordinaryEarnedAndGifted: 12,
      hasGeneralManagerPersonalWallet: false,
      generalManagerPersonal: 1000000,
    ), 12);
  });

  test('GM profile: watched ad adds 3 without hiding earned diamonds', () {
    expect(dedaProfileVisibleDiamonds(
      ordinaryEarnedAndGifted: 0,
      hasGeneralManagerPersonalWallet: true,
      generalManagerPersonal: 999600,
    ), 999600);
    expect(dedaProfileVisibleDiamonds(
      ordinaryEarnedAndGifted: 3,
      hasGeneralManagerPersonalWallet: true,
      generalManagerPersonal: 999600,
    ), 999603);
  });

  test('GM profile: normal account rewards and GM test budget never cross users', () {
    expect(dedaProfileVisibleDiamonds(
      ordinaryEarnedAndGifted: 18,
      hasGeneralManagerPersonalWallet: false,
      generalManagerPersonal: 999600,
    ), 18);
    expect(dedaProfileVisibleDiamonds(
      ordinaryEarnedAndGifted: 18,
      hasGeneralManagerPersonalWallet: true,
      generalManagerPersonal: 0,
    ), 18);
  });

  test('uninitialized balance values never render negatives', () {
    expect(dedaProfileVisibleDiamonds(
      ordinaryEarnedAndGifted: -3,
      hasGeneralManagerPersonalWallet: true,
      generalManagerPersonal: -4,
    ), 0);
  });
}
