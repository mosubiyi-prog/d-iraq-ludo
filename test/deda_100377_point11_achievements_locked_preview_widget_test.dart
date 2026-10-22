import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_100377_level_achievements_page_staged.dart';
import 'package:d_iraq_ludo/deda_100377_level_achievement_badges_policy.dart';

void main() {
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
