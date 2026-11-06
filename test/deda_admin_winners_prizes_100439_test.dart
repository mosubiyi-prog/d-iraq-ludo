import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/deda_admin_league_winners_prizes.dart';

const week = '2026-10-31';
const first = '@DEDA-AAAA11';
const second = '@DEDA-BBBB22';

MapEntry<String, Map<String, dynamic>> score(
  String id, String name, int tasks, int when,
) => MapEntry(id, {
  'weekId': week,
  'publicId': id,
  'displayName': name,
  'weeklyXp': tasks * 20,
  'completedTasks': tasks,
  'updatedAt': Timestamp.fromMillisecondsSinceEpoch(when),
});

Map<String, dynamic> receipt(String id, int rank, int value, String status) => {
  'giftId': DedaWeeklyPrizeProjection.giftId(week, id),
  'sourceType': 'weekly_league',
  'targetPublicId': id,
  'targetName': 'صاحب الجائزة',
  'amount': value,
  'status': status,
  'reason': 'جائزة دوري DEDA — الأسبوع $week — المركز $rank',
};

DedaWeeklyPrizeReport report({
  Map<String, Map<String, dynamic>>? gifts,
  Set<String> frozen = const {},
  List<dynamic>? plan,
}) => DedaWeeklyPrizeProjection.merge(
  week: week,
  scores: [
    score(first, 'هناء', 27, 100),
    score(second, 'سالم حسن', 11, 200),
  ],
  gifts: gifts ?? const {},
  frozen: frozen,
  plan: plan,
);

void main() {
  test('read-only true rank 1 and 2 retain 250/200 with separately tracked Hadaya status', () {
    final r = report(gifts: {
      DedaWeeklyPrizeProjection.giftId(week, first):
        receipt(first, 1, 250, 'received'),
      DedaWeeklyPrizeProjection.giftId(week, second):
        receipt(second, 2, 200, 'pending'),
    });
    expect(r.rows.length, 2);
    expect(r.rows.map((e) => e.place), [1, 2]);
    expect(r.rows.map((e) => e.amount), [250, 200]);
    expect(r.rows[0].status, DedaWeeklyGiftStatus.received);
    expect(r.rows[1].status, DedaWeeklyGiftStatus.pending);
    expect(r.rows[0].originalId, first);
    expect(r.rows[1].originalId, second);
  });

  test('unissued prizes are not falsely marked delivered or claimed', () {
    final r = report();
    expect(r.rows.length, 2);
    expect(r.rows.every((e) => e.status == DedaWeeklyGiftStatus.notCreated),
      true);
  });

  test('frozen account retains its rank but is not shown as paid', () {
    final r = report(frozen: {first});
    expect(r.rows[0].place, 1);
    expect(r.rows[0].status, DedaWeeklyGiftStatus.frozen);
  });

  test('forged or mismatched server receipt visibly requires audit', () {
    final fake = receipt(first, 1, 250, 'received');
    fake['amount'] = 9999;
    final r = report(gifts: {
      DedaWeeklyPrizeProjection.giftId(week, first): fake,
    });
    expect(r.rows[0].status, DedaWeeklyGiftStatus.review);
  });

  test('invalid plan never silently falls back to invented diamonds', () {
    expect(() => report(plan: [1, 2]), throwsStateError);
    expect(() => report(plan: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
      throwsStateError);
  });

  test('all TEN participants receive separate unique positions and only ten rows', () {
    final users = [
      for (var i = 0; i < 12; i++)
        score('@DEDA-T${i.toString().padLeft(5, '0')}',
          'فائز ${i+1}', 30 - i, 1000 + i),
    ];
    final r = DedaWeeklyPrizeProjection.merge(
      week: week,
      scores: users,
      gifts: const {},
      frozen: const {},
    );
    expect(r.rows.length, 10);
    expect(r.rows.map((e) => e.place), List.generate(10, (i) => i + 1));
    expect(r.rows.map((e) => e.amount),
      [250, 200, 150, 100, 100, 100, 100, 100, 100, 100]);
    expect(r.rows.map((e) => e.originalId).toSet().length, 10);
  });

  // Portrait small phones + landscape phones + portrait/landscape tablets.
  // Same four columns as the owner's reference, never duplicate cards.
  const screens = <String, Size>{
    'small phone portrait': Size(320, 568),
    'phone portrait': Size(390, 844),
    'large phone portrait': Size(600, 960),
    'phone landscape': Size(640, 360),
    'wide phone landscape': Size(844, 390),
    'tablet portrait': Size(800, 1280),
    'tablet landscape': Size(1280, 800),
    'compact tablet landscape': Size(1024, 600),
  };
  for (final entry in screens.entries) {
    final size = entry.value;
    testWidgets('one compact four-column report on ${entry.key} ${size.width}x${size.height}',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final live = report(gifts: {
        DedaWeeklyPrizeProjection.giftId(week, first):
          receipt(first, 1, 250, 'received'),
        DedaWeeklyPrizeProjection.giftId(week, second):
          receipt(second, 2, 200, 'pending'),
      });
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Padding(
          padding: const EdgeInsets.all(16),
          child: DedaAdminLeagueWinnersPrizes(
            isArabic: true,
            testNow: DateTime.utc(2026, 11, 7, 3, 1),
            testLoad: (_) async => live,
          ),
        )),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('deda-admin-winners-prizes-table')),
        findsOneWidget);
      for (final label in ['المركز','المستخدم','الجائزة','الحالة',
        'هناء','سالم حسن','250 ماسة','200 ماسة','تم الاستلام',
        'بانتظار الاستلام']) {
        expect(find.text(label), findsOneWidget);
      }
      // TableRow is NOT a Widget, so its key is not found by find.byKey.
      // Check the two actual separate rank cells and visible table structure.
      expect(find.text('🥇 1'), findsOneWidget);
      expect(find.text('🥈 2'), findsOneWidget);
      final table = tester.widget<Table>(
        find.byKey(const Key('deda-admin-winners-prizes-table')));
      expect(table.children.length, 3); // header + exactly two winners
      expect(table.children.every((row) => row.children.length == 4), true);
      final names = <String>[];
      for (final row in table.children.skip(1)) {
        final user = (row.children[1] as Padding).child as Column;
        names.add((user.children.first as Text).data!);
      }
      expect(names, ['هناء', 'سالم حسن']);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('before completed week never fabricates a winner report',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DedaAdminLeagueWinnersPrizes(
        isArabic: true,
        testNow: DateTime.utc(2026, 11, 7, 2, 59),
        testLoad: (_) async => report(),
      )),
    ));
    expect(find.byKey(const Key('deda-admin-winners-prizes-table')),
      findsNothing);
    expect(find.textContaining('بعد اكتمال الأسبوع'), findsOneWidget);
  });
}
