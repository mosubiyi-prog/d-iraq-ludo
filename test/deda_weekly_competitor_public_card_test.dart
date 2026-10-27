import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/deda_weekly_competitor_public_card.dart';

void main() {
  const verified=DedaWeeklyPublicCompetitor(
    participantId:'verified_participant_001',
    originalPublicId:'@DEDA-ABC123',
    activePublicId:'@DEDA-IRAQI',
    displayName:'متصدر ديدا',
    rankVerified:true,
    publicOwnerVerified:true,
    equippedAppearanceVerified:true,
    avatarStyle:2,
    equippedFrameStyle:9,
  );

  test('authentic owned appearance, alias minimum four, unsafe names rejected',(){
    expect(verified.safePublicIdentity,isTrue);
    expect(verified.canShowEquippedFrame,isTrue);
    expect(const DedaWeeklyPublicCompetitor(
      participantId:'verified_participant_001',
      originalPublicId:'@DEDA-ABC123',activePublicId:'@DEDA-AAAA',
      displayName:'متصدر ديدا',
      rankVerified:true,publicOwnerVerified:true,
      equippedAppearanceVerified:true,
      avatarStyle:2,equippedFrameStyle:9,
    ).safePublicIdentity,isTrue);
    expect(const DedaWeeklyPublicCompetitor(
      participantId:'verified_participant_001',
      originalPublicId:'@DEDA-ABC123',activePublicId:'@DEDA-AAAA',
      displayName:'رقم 07712345678',
      rankVerified:true,publicOwnerVerified:true,
      equippedAppearanceVerified:true,
      avatarStyle:2,equippedFrameStyle:9,
    ).safePublicIdentity,isFalse);
    expect(verified.isOtherVerifiedParticipant(verified.participantId),isFalse);
  });

  testWidgets('verified opponent with actual equipped frame opens real app action hooks',
      (tester)async{
    var opened=0,requested=0,rendered=0;
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:
      Center(child:DedaWeeklyCompetitorCard(
        profile:verified,viewerParticipantId:'verified_participant_002',
        relation:DedaWeeklyFriendRelation.notFriends,
        drawOriginalEquippedAvatar:(context,avatar,frame,size){
          rendered++;
          expect(avatar,2);expect(frame,9);
          return const Icon(Icons.account_circle);
        },
        onOpenExistingPublicProfile:(target)async{
          expect(target.originalPublicId,'@DEDA-ABC123');opened++;
        },
        onSendExistingFriendRequest:(target)async{
          expect(target.activePublicId,'@DEDA-IRAQI');requested++;
        },
      )),
    )));
    expect(rendered,greaterThan(0));
    await tester.tap(find.text('متصدر ديدا'));
    await tester.pumpAndSettle();
    expect(find.text('مشاهدة الملف الشخصي'),findsOneWidget);
    expect(find.text('إرسال طلب صداقة'),findsOneWidget);
    await tester.tap(find.text('إرسال طلب صداقة'));
    await tester.pumpAndSettle();
    expect(requested,1);expect(opened,0);
    await tester.tap(find.text('متصدر ديدا').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('مشاهدة الملف الشخصي'));
    await tester.pumpAndSettle();
    expect(opened,1);
  });

  testWidgets('pending relation does not offer another request',(tester)async{
    var requests=0;
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:
      DedaWeeklyCompetitorCard(
        profile:verified,viewerParticipantId:'verified_participant_002',
        relation:DedaWeeklyFriendRelation.pending,
        onOpenExistingPublicProfile:(_)async{},
        onSendExistingFriendRequest:(_)async{requests++;},
      ))));
    await tester.tap(find.text('متصدر ديدا'));
    await tester.pumpAndSettle();
    expect(find.text('طلب الصداقة قيد الانتظار'),findsOneWidget);
    expect(find.text('إرسال طلب صداقة'),findsNothing);
    expect(requests,0);
  });

  testWidgets('self participant and absent verified server evidence are not clickable',
      (tester)async{
    var frames=0, requests=0;
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:
      DedaWeeklyCompetitorCard(
        profile:verified,viewerParticipantId:verified.participantId,
        relation:DedaWeeklyFriendRelation.notFriends,
        drawOriginalEquippedAvatar:(_,a,f,s){
          frames++;return const Icon(Icons.person);
        },
        onSendExistingFriendRequest:(_)async{requests++;},
      ))));
    expect(frames,greaterThan(0));
    await tester.tap(find.text('متصدر ديدا'));
    await tester.pumpAndSettle();
    expect(find.text('إرسال طلب صداقة'),findsNothing);
    expect(requests,0);
    await tester.pumpWidget(const MaterialApp(home:Scaffold(body:
      DedaWeeklyCompetitorCard(
        profile:null,viewerParticipantId:'verified_participant_002',
      ))));
    expect(find.text('—'),findsNWidgets(2));
    expect(find.text('مشاهدة الملف الشخصي'),findsNothing);
  });

  testWidgets('no equipped-appearance proof never borrows premium frame',
      (tester)async{
    var frames=0;
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:
      DedaWeeklyCompetitorCard(
        profile:const DedaWeeklyPublicCompetitor(
          participantId:'verified_participant_001',
          originalPublicId:'@DEDA-ABC123',
          activePublicId:'@DEDA-IRAQI',
          displayName:'متصدر ديدا',
          rankVerified:true,publicOwnerVerified:true,
          equippedAppearanceVerified:false,
          avatarStyle:2,equippedFrameStyle:9,
        ),
        viewerParticipantId:'verified_participant_002',
        drawOriginalEquippedAvatar:(_,a,f,s){
          frames++;return const Icon(Icons.person);
        },
      ))));
    expect(frames,0);
  });
}
