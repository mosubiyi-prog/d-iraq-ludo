import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/deda_admin_league_live_data.dart';
import '../lib/deda_admin_league_live_widgets.dart';

const first = DedaAdminLeagueRow(
    publicId:'@DEDA-AAAA11',name:'المتصدر الأول',
    xp:60,completedTasks:3,updatedMillis:1,place:1);
const second = DedaAdminLeagueRow(
    publicId:'@DEDA-BBBB22',name:'المتصدر الثاني',
    xp:40,completedTasks:2,updatedMillis:2,place:2);

void main() {
  testWidgets('GM live top-ten reads the SAME shared score rows',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DedaAdminLeagueLiveStandings(
        isArabic:true,
        injectedRows:Stream.value(const [first,second]),
      )),
    ));
    await tester.pump();
    expect(find.text('المتصدر الأول'), findsOneWidget);
    expect(find.text('المتصدر الثاني'), findsOneWidget);
    expect(find.text('60 XP'), findsOneWidget);
    expect(find.text('40 XP'), findsOneWidget);
    expect(find.text('@DEDA-AAAA11'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('same top-three projection uses live rows not dummy users',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DedaAdminLeagueLivePodium(
        isArabic:true,
        injectedRows:Stream.value(const [first,second]),
      )),
    ));
    await tester.pump();
    expect(find.text('المتصدر الأول'), findsOneWidget);
    expect(find.text('المتصدر الثاني'), findsOneWidget);
    expect(find.text('60 XP'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('GM monthly history opens true previous frozen week',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DedaAdminLeagueLiveArchive(
        isArabic:true,
        injectedWeeks:Future.value([
          DedaAdminLeagueWeek(
            id:'2026-10-31', rows:const [first,second],
            finishedAt:DateTime.utc(2026,11,7,3)),
        ]),
      )),
    ));
    await tester.pump();
    expect(find.text('الأسبوع 2026-10-31'), findsOneWidget);
    await tester.tap(find.text('الأسبوع 2026-10-31'));
    await tester.pumpAndSettle();
    expect(find.text('1. المتصدر الأول'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
