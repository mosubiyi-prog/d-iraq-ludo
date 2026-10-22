import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:d_iraq_ludo/main.dart';

void main() {
  test('Point09: locally owned badge and active selection survive reopen but never leak to another phone account', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final previousPhone = DedaPreferences.phone;
    final previousFrame = DedaPreferences.profileFrameStyle;
    addTearDown(() {
      DedaPreferences.phone = previousPhone;
      DedaPreferences.profileFrameStyle = previousFrame;
    });
    const accountA = '+9647701111111';
    const accountB = '+9647702222222';
    DedaPreferences.profileFrameStyle = 0;
    DedaPreferences.phone = accountA;
    await DedaStyleInventory.addOwned('badge_spark');
    await DedaStyleInventory.toggleBadge('badge_spark');
    final a = await DedaStyleInventory.load();
    expect(a.owned.contains('badge_spark'), isTrue);
    expect(a.activeBadges, contains('badge_spark'));
    expect(DedaStyleInventory.activeBadgeNotifier.value, 'badge_spark');

    DedaPreferences.phone = accountB;
    final b = await DedaStyleInventory.load();
    expect(b.owned.contains('badge_spark'), isFalse);
    expect(b.activeBadges, contains('badge_member'));
    expect(DedaStyleInventory.activeBadgeNotifier.value, 'badge_member');

    // Switching BACK may restore A's recorded local choices, not B's.
    DedaPreferences.phone = accountA;
    final again = await DedaStyleInventory.load();
    expect(again.owned.contains('badge_spark'), isTrue);
    expect(again.activeBadges, contains('badge_spark'));
    // The original SharedPreferences namespace is unchanged.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().where((key) =>
      key.startsWith('deda_style_inventory_v1_')).length, 1);
  });
}
