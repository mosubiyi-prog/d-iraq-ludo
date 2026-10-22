import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:d_iraq_ludo/main.dart';

void main() {
  test('Point09: pending owned-badge write cannot jump from A to B', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final previousPhone = DedaPreferences.phone;
    final previousFrame = DedaPreferences.profileFrameStyle;
    addTearDown(() {
      DedaPreferences.phone = previousPhone;
      DedaPreferences.profileFrameStyle = previousFrame;
    });
    DedaPreferences.profileFrameStyle = 0;
    DedaPreferences.phone = '+9647703333333';
    final pendingA = DedaStyleInventory.addOwned('badge_royal');
    // Switch synchronously while A is waiting on SharedPreferences.
    DedaPreferences.phone = '+9647704444444';
    await pendingA;
    final b = await DedaStyleInventory.load();
    expect(b.owned, isNot(contains('badge_royal')));
    expect(b.activeBadges, contains('badge_member'));
    DedaPreferences.phone = '+9647703333333';
    final a = await DedaStyleInventory.load();
    expect(a.owned, isNot(contains('badge_royal')));
  });

  test('Point09: pending badge activation never overrides next account notifier', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final previousPhone = DedaPreferences.phone;
    final previousFrame = DedaPreferences.profileFrameStyle;
    addTearDown(() {
      DedaPreferences.phone = previousPhone;
      DedaPreferences.profileFrameStyle = previousFrame;
    });
    DedaPreferences.profileFrameStyle = 0;
    DedaPreferences.phone = '+9647705555555';
    await DedaStyleInventory.addOwned('badge_spark');
    final aPendingActivate = DedaStyleInventory.toggleBadge('badge_spark');
    DedaPreferences.phone = '+9647706666666';
    await aPendingActivate;
    final b = await DedaStyleInventory.load();
    expect(b.activeBadges, contains('badge_member'));
    expect(DedaStyleInventory.activeBadgeNotifier.value, 'badge_member');
    DedaPreferences.phone = '+9647705555555';
    final restored = await DedaStyleInventory.load();
    expect(restored.owned, contains('badge_spark'));
    expect(restored.activeBadges, contains('badge_member'));
  });

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
