import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/deda_weekly_leaderboard_page.dart';
import '../lib/deda_weekly_leaderboard_policy.dart';

void main() {
  const canvasKey = ValueKey<String>('deda-weekly-leaderboard-stage');

  DedaLeaderboardViewData verifiedFixture() {
    final scores = List<DedaWeeklyLeaderboardRow>.generate(12, (i) {
      return DedaWeeklyLeaderboardRow(
        place: i + 1,
        accountUid: 'tester-' + (i + 1).toString(),
        weeklyPoints: (12 - i) * 20,
        verifiedTaskCompletions: 12 - i,
        diamondsIfFinalWinner:
            DedaWeeklyLeaderboardPolicy.diamondsForFinalPlace(i + 1),
      );
    });
    return DedaLeaderboardViewData(
      verified: true,
      rows: scores,
      viewerUid: 'tester-12',
      profilesByUid: <String, DedaLeaderboardProfile>{
        for (var i = 1; i <= 12; i++)
          'tester-$i': DedaLeaderboardProfile(
            accountUid: 'tester-$i',
            displayName: 'مستخدم تجريبي $i',
            activePublicId: '@DEDA-TEST' + i.toString().padLeft(3, '0'),
          ),
      },
      remainingUntilWeekEnd: const Duration(hours: 16),
    );
  }

  final screens = <Size>[
    const Size(320, 568),
    const Size(390, 844),
    const Size(412, 915),
    const Size(600, 960),
    const Size(800, 1280),
    const Size(1024, 1366),
    const Size(1280, 800),
    const Size(2560, 1600),
  ];

  for (final screen in screens) {
    testWidgets('whole weekly leaderboard fits $screen without scroll',
        (tester) async {
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(MaterialApp(
        home: DedaWeeklyLeaderboardPage(
          current: verifiedFixture(),
          previous: verifiedFixture(),
        ),
      ));

      final stage = find.byKey(canvasKey);
      expect(stage, findsOneWidget);
      final stageSize = tester.getSize(stage);
      final expectedWidth = math.min(screen.width, screen.height * 2 / 3);
      expect(stageSize.width, closeTo(expectedWidth, .02));
      expect(stageSize.height, closeTo(screen.height, .02));
      expect(stageSize.width, lessThanOrEqualTo(screen.width));

      final rect = tester.getRect(stage);
      expect(rect.left, closeTo((screen.width - expectedWidth) / 2, .02));
      expect(rect.right, closeTo((screen.width + expectedWidth) / 2, .02));

      expect(find.byType(Scrollable), findsNothing);
      expect(find.text('متصدرين المهام'), findsOneWidget);
      expect(find.text('الأسبوع الحالي'), findsOneWidget);
      expect(find.text('الأسبوع السابق'), findsOneWidget);
      expect(find.text('النقاط المكتسبة'), findsNWidgets(2));
      expect(find.text('مستخدم تجريبي 1'), findsOneWidget);
      expect(find.text('مستخدم تجريبي 12'), findsOneWidget);
      expect(find.textContaining('150 ماسة'), findsWidgets);
      expect(find.textContaining('10 ماسات'), findsWidgets);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('الأسبوع السابق'));
      await tester.pump();
      expect(find.byType(Scrollable), findsNothing);
      expect(tester.getSize(stage), stageSize);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('screen respects Android status/navigation safe insets',
      (tester) async {
    const size = Size(800, 1280);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 32, bottom: 24);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetPadding();
    });
    await tester.pumpWidget(MaterialApp(
      home: DedaWeeklyLeaderboardPage(current: verifiedFixture()),
    ));
    final stage = tester.getRect(find.byKey(canvasKey));
    expect(stage.top, greaterThanOrEqualTo(32));
    expect(stage.bottom, lessThanOrEqualTo(1280 - 24));
    expect(find.byType(Scrollable), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
