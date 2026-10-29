import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:d_iraq_ludo/deda_weekly_leaderboard_page.dart';
import 'package:d_iraq_ludo/deda_weekly_leaderboard_policy.dart';
import 'package:d_iraq_ludo/deda_weekly_competitor_public_card.dart';

const viewer = 'leader-participant-viewer-00000001';

DedaWeeklyPublicCompetitor verified(int place) {
  final id = place.toString().padLeft(6, '0');
  return DedaWeeklyPublicCompetitor(
    participantId: 'leader-participant-rank-$id-verified',
    originalPublicId: '@DEDA-$id',
    activePublicId: '@DEDA-$id',
    displayName: 'متصدر $place',
    rankVerified: true,
    publicOwnerVerified: true,
    equippedAppearanceVerified: true,
    avatarStyle: 2,
    equippedFrameStyle: 3,
  );
}

DedaLeaderboardViewData standings({
  bool verifiedRank2 = true,
  bool viewerIsRank2 = false,
}) {
  final rows = List.generate(10, (i) {
    final position = i + 1;
    return DedaWeeklyLeaderboardRow(
      place: position,
      accountUid: verified(position).participantId,
      weeklyPoints: (11 - position) * 20,
      verifiedTaskCompletions: 11 - position,
      diamondsIfFinalWinner:
          DedaWeeklyLeaderboardPolicy.diamondsForFinalPlace(position),
    );
  });
  final profiles = <String, DedaLeaderboardProfile>{};
  for (var place = 1; place <= 10; place++) {
    final user = verified(place);
    profiles[user.participantId] = DedaLeaderboardProfile(
      accountUid: user.participantId,
      displayName: user.displayName,
      activePublicId: user.activePublicId,
      verifiedCompetitor: place == 2 && !verifiedRank2 ? null : user,
    );
  }
  return DedaLeaderboardViewData(
    verified: true,
    rows: rows,
    viewerUid: viewerIsRank2 ? verified(2).participantId : viewer,
    profilesByUid: profiles,
    remainingUntilWeekEnd: const Duration(days: 2),
  );
}

Future<void> mount(
  WidgetTester tester, {
  required DedaLeaderboardViewData current,
  Future<void> Function(DedaWeeklyPublicCompetitor)? open,
  Future<void> Function(DedaWeeklyPublicCompetitor)? friend,
  DedaWeeklyFriendRelation Function(DedaWeeklyPublicCompetitor)? relation,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(MaterialApp(home: DedaWeeklyLeaderboardPage(
    current: current,
    onOpenExistingPublicProfile: open,
    onSendExistingFriendRequest: friend,
    friendRelationFor: relation,
  )));
  await tester.pump();
}

void main() {
  testWidgets('second-place whole podium opens verified public profile',
      (tester) async {
    final opened = <String>[];
    await mount(tester,
      current: standings(),
      open: (p) async => opened.add(p.participantId),
      relation: (_) => DedaWeeklyFriendRelation.notFriends,
    );
    final second = find.byKey(const ValueKey<String>('deda_weekly_rank_2_tap'));
    expect(second, findsOneWidget);
    expect(find.byType(Scrollable), findsNothing);
    await tester.tap(second);
    await tester.pumpAndSettle();
    expect(find.text('مشاهدة الملف الشخصي'), findsOneWidget);
    await tester.tap(find.text('مشاهدة الملف الشخصي'));
    await tester.pumpAndSettle();
    expect(opened, [verified(2).participantId]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('whole lower table row opens friendship action once',
      (tester) async {
    final requested = <String>[];
    await mount(tester,
      current: standings(),
      friend: (p) async => requested.add(p.participantId),
      relation: (_) => DedaWeeklyFriendRelation.notFriends,
    );
    final row = find.byKey(const ValueKey<String>('deda_weekly_rank_4_tap'));
    expect(row, findsOneWidget);
    expect(find.byKey(const ValueKey<String>('deda_weekly_rank_10_tap')),
        findsOneWidget);
    await tester.tap(row);
    await tester.pumpAndSettle();
    await tester.tap(find.text('إرسال طلب صداقة'));
    await tester.pumpAndSettle();
    expect(requested, [verified(4).participantId]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rank 2 with no authenticated appearance/identity stays disabled',
      (tester) async {
    var opened = 0;
    await mount(tester,
      current: standings(verifiedRank2: false),
      open: (_) async => opened++,
    );
    final target = find.byKey(const ValueKey<String>('deda_weekly_rank_2_tap'));
    final ink = tester.widget<InkWell>(target);
    expect(ink.onTap, isNull);
    await tester.tap(target);
    await tester.pump();
    expect(find.text('مشاهدة الملف الشخصي'), findsNothing);
    expect(opened, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('viewer cannot initiate own profile or friend action through rank 2',
      (tester) async {
    var opened = 0;
    await mount(tester,
      current: standings(viewerIsRank2: true),
      open: (_) async => opened++,
      relation: (_) => DedaWeeklyFriendRelation.notFriends,
    );
    final ink = tester.widget<InkWell>(
      find.byKey(const ValueKey<String>('deda_weekly_rank_2_tap')));
    expect(ink.onTap, isNull);
    expect(opened, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no verified social adapter means no fake action or payout',
      (tester) async {
    await mount(tester, current: standings());
    for (final place in [1, 2, 3, 4, 7, 10]) {
      final ink = tester.widget<InkWell>(
        find.byKey(ValueKey<String>('deda_weekly_rank_${place}_tap')));
      expect(ink.onTap, isNull, reason: 'rank $place must not suggest enabled action');
    }
    expect(find.byType(Scrollable), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet landscape keeps positions 2 and 4 reachable',
      (tester) async {
    await mount(tester,
      current: standings(),
      size: const Size(960, 600),
      open: (_) async {},
    );
    expect(find.byKey(const ValueKey<String>('deda_weekly_rank_2_tap')),
        findsOneWidget);
    expect(find.byKey(const ValueKey<String>('deda_weekly_rank_4_tap')),
        findsOneWidget);
    expect(find.byType(Scrollable), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
