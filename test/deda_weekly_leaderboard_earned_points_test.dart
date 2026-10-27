import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/deda_weekly_leaderboard_page.dart';
import '../lib/deda_weekly_leaderboard_policy.dart';

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(600, 960),
  ]) {
    testWidgets('Weekly earned points labelled on ${size.width}x${size.height} without scrolling',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      const row = DedaWeeklyLeaderboardRow(
        place: 1,
        accountUid: 'verifiedAccount',
        weeklyPoints: 75,
        verifiedTaskCompletions: 5,
        diamondsIfFinalWinner: 150,
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: DedaWeeklyLeaderboardPage(
            current: DedaLeaderboardViewData(
              verified: true,
              rows: [row],
              viewerUid: 'verifiedAccount',
              profilesByUid: {
                'verifiedAccount': DedaLeaderboardProfile(
                  accountUid: 'verifiedAccount',
                  displayName: 'حساب موثق للاختبار فقط',
                  activePublicId: '@DEDA-TESTER',
                ),
              },
            ),
          ),
        ),
      );

      expect(find.text('النقاط المكتسبة'), findsNWidgets(2));
      expect(find.text('75 نقطة'), findsWidgets);
      expect(find.textContaining('رصيد حسابك ومستواك محفوظان'),
          findsOneWidget);
      expect(find.byType(Scrollable), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byTooltip('معلومات المنافسة'));
      await tester.pumpAndSettle();
      expect(find.textContaining('شلون تحصل على نقاط الدوري؟'),
          findsOneWidget);
      expect(find.textContaining('10 نقاط لتسجيل الدخول اليومي'),
          findsOneWidget);
      expect(find.textContaining('5 نقاط لكل إجابة مرورية صحيحة'),
          findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('حسناً'));
      await tester.pumpAndSettle();
      expect(find.byType(Scrollable), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
