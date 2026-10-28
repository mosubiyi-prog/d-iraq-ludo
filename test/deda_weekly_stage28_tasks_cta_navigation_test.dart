import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_weekly_leaderboard_page.dart';
import 'package:d_iraq_ludo/deda_weekly_leaderboard_safe_screen.dart';

class OriginalTasksStub extends StatelessWidget {
  const OriginalTasksStub({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(child: Text('DEDA original daily tasks destination')),
  );
}

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(800, 1200),
  ]) {
    testWidgets('current league CTA opens existing task route at $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      var opens = 0;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) => DedaWeeklyLeaderboardSafeScreen(
          onOpenDailyTasks: () {
            opens++;
            Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const OriginalTasksStub(),
            ));
          },
        )),
      ));
      expect(find.byKey(const Key('deda_weekly_continue_daily_tasks')),
          findsOneWidget);
      expect(find.byType(Scrollable), findsNothing);
      await tester.tap(find.byKey(const Key('deda_weekly_continue_daily_tasks')));
      await tester.pumpAndSettle();
      expect(opens, 1);
      expect(find.text('DEDA original daily tasks destination'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('previous-week tab still opens the SAME original daily tasks',
      (tester) async {
    var opens = 0;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => DedaWeeklyLeaderboardSafeScreen(
        onOpenDailyTasks: () {
          opens++;
          Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => const OriginalTasksStub(),
          ));
        },
      )),
    ));
    await tester.tap(find.text('الأسبوع السابق'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('deda_weekly_continue_daily_tasks')));
    await tester.pumpAndSettle();
    expect(opens, 1);
    expect(find.text('DEDA original daily tasks destination'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('without official route callback, CTA does not mutate or navigate',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: DedaWeeklyLeaderboardPage(),
    ));
    final control = tester.widget<InkWell>(
      find.byKey(const Key('deda_weekly_continue_daily_tasks')));
    expect(control.onTap, isNull);
    await tester.tap(find.byKey(const Key('deda_weekly_continue_daily_tasks')));
    await tester.pump();
    expect(find.byType(DedaWeeklyLeaderboardPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
