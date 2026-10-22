import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_100377_level_achievements_page_staged.dart';
import 'package:d_iraq_ludo/deda_100377_level_achievement_badges_policy.dart';

void main() {
  testWidgets('owner original six WebP badges are bundled, correct sprite cells, without awarding levels', (tester) async {
    // The 3x2 asset was copied from the actual owner screenshot, not drawn
    // from scratch or substituted by one of the paid cosmetic badges.
    final bytes = await rootBundle.load(DedaOriginalSixLevelBadgeArt.asset);
    expect(bytes.lengthInBytes, 98380);
    expect(bytes.getUint8(0), 0x52); // RIFF/WebP
    expect(bytes.getUint8(1), 0x49);
    expect(bytes.getUint8(8), 0x57);
    expect(bytes.getUint8(9), 0x45);
    tester.view.physicalSize = const Size(440, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(
      home: DedaLevelAchievementsPage(
        verifiedServerLevel: null,
        hasVerifiedAccountAndLevel: false,
      ),
    ));
    await tester.pump();
    for (final tier in DedaLevelBadgeTier.values) {
      expect(find.byKey(ValueKey<String>('deda_owner_level_art_${tier.id}')), findsOneWidget);
      final asset = tester.widget<Image>(
        find.byKey(ValueKey<String>('deda_owner_level_asset_${tier.id}')),
      );
      expect(asset.image, isA<AssetImage>());
      expect((asset.image as AssetImage).assetName,
          DedaOriginalSixLevelBadgeArt.asset);
    }
    expect(find.text('مكتسبة'), findsNothing);
    expect(DedaLevelBadgePolicy.releaseEnabled, isFalse);
  });

  testWidgets('six achievement rows match owner artwork presentation order, no purchase or unverified unlock', (tester) async {
    tester.view.physicalSize = const Size(440, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(
      home: DedaLevelAchievementsPage(
        verifiedServerLevel: null,
        hasVerifiedAccountAndLevel: false,
      ),
    ));
    await tester.pump();
    final order = <DedaLevelBadgeTier>[
      DedaLevelBadgeTier.gold,
      DedaLevelBadgeTier.silver,
      DedaLevelBadgeTier.emerald,
      DedaLevelBadgeTier.diamond,
      DedaLevelBadgeTier.royal,
      DedaLevelBadgeTier.legendary,
    ];
    for (var i = 0; i < order.length - 1; i++) {
      final above = find.byKey(ValueKey<String>('deda_p11_${order[i].id}'));
      final below = find.byKey(ValueKey<String>('deda_p11_${order[i+1].id}'));
      expect(above, findsOneWidget);
      expect(below, findsOneWidget);
      expect(tester.getTopLeft(above).dy,
          lessThan(tester.getTopLeft(below).dy));
    }
    expect(find.text('مكتسبة'), findsNothing);
    expect(find.byKey(const Key('deda_p11_no_unverified_unlock')),
        findsOneWidget);
  });

  testWidgets('Point11 six separate achievement rows explain preliminary ranges without granting badges',
      (tester) async {
    tester.view.physicalSize = const Size(440, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(
      home: DedaLevelAchievementsPage(
        verifiedServerLevel: null,
        hasVerifiedAccountAndLevel: false,
      ),
    ));
    await tester.pump();
    expect(find.text('شاراتك وإنجازاتك'), findsOneWidget);
    expect(find.byKey(const Key('deda_p11_earned_not_purchased')), findsOneWidget);
    expect(find.byKey(const Key('deda_p11_no_unverified_unlock')), findsOneWidget);
    for (final entry in DedaLevelBadgeTier.values) {
      expect(find.byKey(ValueKey<String>('deda_p11_' + entry.id)), findsOneWidget);
      expect(find.text(entry.arabicName), findsOneWidget);
      expect(find.byKey(ValueKey<String>('deda_p11_status_' + entry.id)),
          findsOneWidget);
    }
    expect(find.text('مكتسبة'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.textContaining('شراء'), findsOneWidget); // explicitly says no purchase
  });

  testWidgets('Point11 cannot falsely show earned status even if a caller passes unverified level 70',
      (tester) async {
    tester.view.physicalSize = const Size(440, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(
      home: DedaLevelAchievementsPage(
        verifiedServerLevel: 70,
        hasVerifiedAccountAndLevel: true,
      ),
    ));
    await tester.pump();
    expect(DedaLevelBadgePolicy.releaseEnabled, isFalse);
    expect(find.text('مكتسبة'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('من المستوى 1'), findsOneWidget);
    expect(find.text('من المستوى 10'), findsOneWidget);
    expect(find.text('من المستوى 20'), findsOneWidget);
    expect(find.text('من المستوى 30'), findsOneWidget);
    expect(find.text('من المستوى 40'), findsOneWidget);
    expect(find.text('من المستوى 50'), findsOneWidget);
  });
}
