import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/deda_weekly_leaderboard_page.dart';
import '../lib/deda_weekly_leaderboard_policy.dart';

void main() {
  for (final size in [const Size(320, 568), const Size(390, 844),
                      const Size(600, 960)]) {
    testWidgets('fixed non-scrolling leaderboard fits ${size.width}x${size.height}',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        const MaterialApp(home: DedaWeeklyLeaderboardPage()),
      );
      expect(find.byType(Scrollable), findsNothing);
      expect(find.byType(ListView), findsNothing);
      expect(find.byType(DedaWeeklyLeaderboardPage), findsOneWidget);
      expect(find.text('متصدرين المهام'), findsOneWidget);
      expect(find.text('الأسبوع الحالي'), findsOneWidget);
      expect(find.text('الأسبوع السابق'), findsOneWidget);
      expect(find.text('— نقطة'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('الأسبوع السابق'));
      await tester.pump();
      expect(find.byType(Scrollable), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('verified 12th position shown, but only ten prizes',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final rows = List.generate(12, (n) =>
        DedaWeeklyLeaderboardRow(
          place: n + 1,
          accountUid: 'user-${n + 1}',
          weeklyPoints: 100 - n,
          verifiedTaskCompletions: 3,
          diamondsIfFinalWinner:
              DedaWeeklyLeaderboardPolicy.diamondsForFinalPlace(n + 1),
        ));

    await tester.pumpWidget(MaterialApp(
      home: DedaWeeklyLeaderboardPage(
        current: DedaLeaderboardViewData(
          verified: true,
          rows: rows,
          viewerUid: 'user-12',
          profilesByUid: const {
            'user-1': DedaLeaderboardProfile(
              accountUid: 'user-1',
              displayName: 'اختبار حساب موثق',
              activePublicId: '@DEDA-TEST1',
            ),
          },
          remainingUntilWeekEnd: const Duration(days: 2, hours: 3),
        ),
      ),
    ));
    expect(find.text('اختبار حساب موثق'), findsOneWidget);
    expect(find.text('2 يوم 3 س'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.byType(Scrollable), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
