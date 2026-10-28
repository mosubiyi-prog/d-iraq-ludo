import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/deda_weekly_competitor_public_card.dart';
import '../lib/deda_weekly_leaderboard_safe_screen.dart';

void main() {
  Map<String, Object?> packet({bool verified = true}) {
    final first = <String, Object?>{
      'place': 1,
      'participantId': 'verified-participant-0001',
      'displayName': 'المتصدر الأول',
      'activePublicId': '@DEDA-AAAA',
      'weeklyPoints': 60,
      'verifiedTaskCompletions': 3,
      'diamondsIfFinalWinner': 150,
    };
    final second = <String, Object?>{
      'place': 2,
      'participantId': 'verified-participant-0002',
      'displayName': 'المتصدر الثاني',
      'activePublicId': '@DEDA-BBBB',
      'weeklyPoints': 40,
      'verifiedTaskCompletions': 2,
      'diamondsIfFinalWinner': 100,
      'publicAppearance': <String, Object?>{
        'originalPublicId': '@DEDA-A1B2C3',
        'activePublicId': '@DEDA-BBBB',
        'displayName': 'المتصدر الثاني',
        'avatarStyle': 2,
        'equippedFrameStyle': 9,
        'publicOwnerVerified': true,
        'equippedAppearanceVerified': true,
      },
    };
    Map<String, Object?> week(String status) => <String, Object?>{
      'verified': verified,
      'weekId': 'server-$status',
      'status': status,
      'rows': status == 'live' ? <Map<String, Object?>>[first, second]
          : <Map<String, Object?>>[],
      'viewerParticipantId':
          status == 'live' ? 'verified-participant-0001' : null,
      'viewerPlace': status == 'live' ? 1 : null,
      'remainingMs': status == 'live' ? 90000 : 0,
      'rewardsCredited': false,
    };
    return <String, Object?>{
      'source': 'future_server_issued_only',
      'readOnly': true,
      'current': week('live'),
      'previous': week('closed'),
    };
  }

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  testWidgets('rank two opens original profile / friend action only with verified data',
      (tester) async {
    phone(tester);
    var opened = 0, requested = 0, frames = 0;
    await tester.pumpWidget(MaterialApp(
      home: DedaWeeklyLeaderboardSafeScreen(
        loadVerifiedStandings: () async => packet(),
        currentAccountStillAuthorized: () => true,
        friendRelationFor: (_) => DedaWeeklyFriendRelation.notFriends,
        drawOriginalEquippedAvatar: (context, avatar, frame, size) {
          expect(avatar, 2);
          expect(frame, 9);
          frames++;
          return const Icon(Icons.verified);
        },
        onOpenExistingPublicProfile: (person) async {
          expect(person.originalPublicId, '@DEDA-A1B2C3');
          opened++;
        },
        onSendExistingFriendRequest: (person) async {
          expect(person.activePublicId, '@DEDA-BBBB');
          requested++;
        },
      ),
    ));
    await tester.pumpAndSettle();
    expect(frames, greaterThan(0));
    expect(find.byType(Scrollable), findsNothing);
    await tester.tap(find.text('المتصدر الثاني'));
    await tester.pumpAndSettle();
    expect(find.text('مشاهدة الملف الشخصي'), findsOneWidget);
    expect(find.text('إرسال طلب صداقة'), findsOneWidget);
    await tester.tap(find.text('إرسال طلب صداقة'));
    await tester.pumpAndSettle();
    expect(requested, 1);
    expect(opened, 0);
  });

  testWidgets('logout after opening an action sheet rejects stale action',
      (tester) async {
    phone(tester);
    var active = true, opened = 0;
    await tester.pumpWidget(MaterialApp(
      home: DedaWeeklyLeaderboardSafeScreen(
        loadVerifiedStandings: () async => packet(),
        currentAccountStillAuthorized: () => active,
        onOpenExistingPublicProfile: (_) async { opened++; },
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('المتصدر الثاني'));
    await tester.pumpAndSettle();
    expect(find.text('مشاهدة الملف الشخصي'), findsOneWidget);
    active = false;
    await tester.tap(find.text('مشاهدة الملف الشخصي'));
    await tester.pumpAndSettle();
    expect(opened, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unverified snapshot never opens the second competitor profile',
      (tester) async {
    phone(tester);
    var opened = 0;
    await tester.pumpWidget(MaterialApp(
      home: DedaWeeklyLeaderboardSafeScreen(
        loadVerifiedStandings: () async => packet(verified: false),
        currentAccountStillAuthorized: () => true,
        friendRelationFor: (_) => DedaWeeklyFriendRelation.notFriends,
        onOpenExistingPublicProfile: (_) async { opened++; },
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('المتصدر الثاني'), findsNothing);
    expect(find.textContaining('الترتيب قيد التحقق'), findsOneWidget);
    expect(opened, 0);
  });

  testWidgets('missing official social adapters keep podium noninteractive',
      (tester) async {
    phone(tester);
    await tester.pumpWidget(MaterialApp(
      home: DedaWeeklyLeaderboardSafeScreen(
        loadVerifiedStandings: () async => packet(),
        currentAccountStillAuthorized: () => true,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('المتصدر الثاني'));
    await tester.pumpAndSettle();
    expect(find.text('مشاهدة الملف الشخصي'), findsNothing);
    expect(find.text('إرسال طلب صداقة'), findsNothing);
  });
}
