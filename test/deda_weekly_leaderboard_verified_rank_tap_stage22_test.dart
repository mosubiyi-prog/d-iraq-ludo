import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/deda_weekly_leaderboard_page.dart';
import '../lib/deda_weekly_leaderboard_policy.dart';
import '../lib/deda_weekly_competitor_public_card.dart';

void main() {
  const selfToken='verified-participant-222';
  const firstToken='verified-participant-111';

  const trusted=DedaWeeklyPublicCompetitor(
    participantId:firstToken,
    originalPublicId:'@DEDA-ABC123',
    activePublicId:'@DEDA-AAAA',
    displayName:'متصدر أصيل',
    rankVerified:true,publicOwnerVerified:true,
    equippedAppearanceVerified:true,
    avatarStyle:2,equippedFrameStyle:9,
  );
  DedaLeaderboardViewData scoreboard({
    DedaWeeklyPublicCompetitor? contestant=trusted,
    String viewer=selfToken,
    int place=1,
  }) => DedaLeaderboardViewData(
    verified:true,
    rows:[
      DedaWeeklyLeaderboardRow(
        place:place, accountUid:firstToken,
        weeklyPoints:40, verifiedTaskCompletions:2,
        diamondsIfFinalWinner:
          DedaWeeklyLeaderboardPolicy.diamondsForFinalPlace(place),
      ),
    ],
    profilesByUid:{
      firstToken:DedaLeaderboardProfile(
        accountUid:firstToken,displayName:'متصدر أصيل',
        activePublicId:'@DEDA-AAAA',
        verifiedCompetitor:contestant,
      ),
    },
    viewerUid:viewer,
    remainingUntilWeekEnd:const Duration(days:3),
  );

  void phone(WidgetTester tester) {
    tester.view.physicalSize=const Size(390,844);
    tester.view.devicePixelRatio=1;
    addTearDown((){
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  testWidgets('real verified podium avatar uses the frame that winner has equipped and tapping shows two actions',
      (tester)async{
    phone(tester);
    var frames=0,open=0,invite=0;
    await tester.pumpWidget(MaterialApp(home:DedaWeeklyLeaderboardPage(
      current:scoreboard(),
      drawOriginalEquippedAvatar:(context,avatar,frame,size){
        frames++;
        expect(avatar,2);expect(frame,9);
        return const Icon(Icons.verified);
      },
      friendRelationFor:(_)=>DedaWeeklyFriendRelation.notFriends,
      onOpenExistingPublicProfile:(person)async{
        expect(person.originalPublicId,'@DEDA-ABC123');open++;
      },
      onSendExistingFriendRequest:(person)async{
        expect(person.activePublicId,'@DEDA-AAAA');invite++;
      },
    )));
    expect(frames,greaterThan(0));
    expect(find.byType(Scrollable),findsNothing);
    await tester.tap(find.text('متصدر أصيل'));
    await tester.pumpAndSettle();
    expect(find.text('مشاهدة الملف الشخصي'),findsOneWidget);
    expect(find.text('إرسال طلب صداقة'),findsOneWidget);
    await tester.tap(find.text('إرسال طلب صداقة'));
    await tester.pumpAndSettle();
    expect(invite,1);expect(open,0);
  });

  testWidgets('real rank 4 identity is tappable; old pending friendship cannot send second request',
      (tester)async{
    phone(tester);
    var requests=0,visited=0;
    await tester.pumpWidget(MaterialApp(home:DedaWeeklyLeaderboardPage(
      current:scoreboard(place:4),
      friendRelationFor:(_)=>DedaWeeklyFriendRelation.pending,
      onOpenExistingPublicProfile:(_)async{visited++;},
      onSendExistingFriendRequest:(_)async{requests++;},
    )));
    expect(find.byType(Scrollable),findsNothing);
    await tester.tap(find.text('متصدر أصيل'));
    await tester.pumpAndSettle();
    expect(find.text('طلب الصداقة قيد الانتظار'),findsOneWidget);
    expect(find.text('إرسال طلب صداقة'),findsNothing);
    await tester.tap(find.text('مشاهدة الملف الشخصي'));
    await tester.pumpAndSettle();
    expect(visited,1);expect(requests,0);
  });

  testWidgets('no trusted frame evidence or no authenticated public-profile callbacks means safe noninteractive rank',
      (tester)async{
    phone(tester);
    var frames=0,visited=0;
    await tester.pumpWidget(MaterialApp(home:DedaWeeklyLeaderboardPage(
      current:scoreboard(contestant:null),
      drawOriginalEquippedAvatar:(_,a,f,s){
        frames++;return const Icon(Icons.person);
      },
      onOpenExistingPublicProfile:(_)async{visited++;},
    )));
    await tester.tap(find.text('متصدر أصيل'));
    await tester.pumpAndSettle();
    expect(frames,0);expect(visited,0);
    expect(find.text('مشاهدة الملف الشخصي'),findsNothing);
  });

  testWidgets('same account must not send itself a friend request from the podium',
      (tester)async{
    phone(tester);
    var count=0;
    await tester.pumpWidget(MaterialApp(home:DedaWeeklyLeaderboardPage(
      current:scoreboard(viewer:firstToken),
      friendRelationFor:(_)=>DedaWeeklyFriendRelation.notFriends,
      onOpenExistingPublicProfile:(_)async{count++;},
      onSendExistingFriendRequest:(_)async{count++;},
    )));
    await tester.tap(find.text('متصدر أصيل').first);
    await tester.pumpAndSettle();
    expect(count,0);
    expect(find.text('إرسال طلب صداقة'),findsNothing);
  });
}
