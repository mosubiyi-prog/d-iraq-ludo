import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_six_admin_users.dart';
import 'package:d_iraq_ludo/deda_six_frame_equip.dart';
import 'package:d_iraq_ludo/deda_six_frame_purchase_action.dart';
import 'package:d_iraq_ludo/deda_qa32_spark_public_identifier_directory.dart';

void main() {
  DedaSixUserRecord row(String id, String key, int day, {int? seen}) =>
    DedaSixUserRecord(id, {'accountKey': key, 'name': id,
      'createdAt': DateTime(2026, 10, day),
      if (seen != null) 'updatedAt': DateTime(2026, 10, seen)});
  test('one stable account despite repeated sessions and newer visits', () {
    final profiles = [row('a', 'a', 1), row('b', 'b', 5)];
    final result = DedaSixAdminUsers.rows(profiles: profiles,
      sessions: [row('a1', 'a', 1, seen: 20), row('a2', 'a', 22), row('b1', 'b', 5)]);
    expect(result.map((r) => r.accountKey), ['b', 'a']);
    expect(result.last.registeredAt, DateTime(2026, 10, 1));
    expect(result.last.ownerUid, 'a2');
  });
  test('legacy session duplicates use first registration, never last visit', () {
    final result = DedaSixAdminUsers.rows(profiles: [], sessions:
      [row('a1','a',1),row('a2','a',22),row('b1','b',5)]);
    expect(result.map((r) => r.accountKey), ['b','a']);
    expect(result.length, 2);
  });
  test('new registration appears first with deterministic ties', () {
    final result = DedaSixAdminUsers.rows(profiles:
      [row('a','a',1),row('b','b',5),row('c','c',23)], sessions: []);
    expect(result.map((r) => r.id), ['c','b','a']);
  });
  test('missing stable identity never invents a user from UID', () {
    final result = DedaSixAdminUsers.rows(profiles: [], sessions:
      [const DedaSixUserRecord('uid', {'name':'same'})]);
    expect(result, isEmpty);
  });
  test('owned frames first under avatars, no duplicates or catalog changes', () {
    final ordered = DedaSixFrameOrder.styles({12,7});
    expect(ordered.take(2), [7,12]); expect(ordered.length,16);
    expect(ordered.toSet(), {for(var i=3;i<=18;i++) i});
  });
  test('equip verifies saves confirms then publishes without purchase', () async {
    final events=<String>[];
    await DedaSixFrameCommit.run(sameAccount:()=>true,
      verifyOwnership:() async {events.add('verify');return true;},
      save:() async {events.add('save');},
      confirm:() async {events.add('confirm');return true;},
      publish:(){events.add('publish');});
    expect(events,['verify','save','confirm','publish']);
  });
  test('unowned frame cannot save or repaint', () async {
    var writes=0;
    await expectLater(DedaSixFrameCommit.run(sameAccount:()=>true,
      verifyOwnership:() async=>false,save:() async{writes++;},
      confirm:() async=>true,publish:(){writes++;}),throwsStateError);
    expect(writes,0);
  });
  test('unconfirmed remote save never claims active', () async {
    var published=false;
    await expectLater(DedaSixFrameCommit.run(sameAccount:()=>true,
      verifyOwnership:() async=>true,save:() async{},
      confirm:() async=>false,publish:(){published=true;}),throwsStateError);
    expect(published,false);
  });
  test('account change during ownership read prevents saving', () async {
    var same=true, saved=false;
    await expectLater(DedaSixFrameCommit.run(sameAccount:()=>same,
      verifyOwnership:() async{same=false;return true;},
      save:() async{saved=true;},confirm:() async=>true,publish:(){}),throwsStateError);
    expect(saved,false);
  });
  test('active alias route accepts only current mutually matching projection', () {
    final active={'originalId':'@DEDA-AQPYXJ','activeId':'@DEDA-IRAQI',
      'baseColor':'gold','updatedAt':null};
    final route={'originalId':'@DEDA-AQPYXJ','aliasId':'@DEDA-IRAQI',
      'baseColor':'gold','updatedAt':null};
    expect(DedaQa32SparkPublicIdentifierDirectory.originalFromProjection(
      '@DEDA-IRAQI',route,active),'@DEDA-AQPYXJ');
    expect(DedaQa32SparkPublicIdentifierDirectory.styleFromProjection(
      '@DEDA-AQPYXJ',active)?['displayId'],'@DEDA-IRAQI');
    expect(DedaQa32SparkPublicIdentifierDirectory.originalFromProjection(
      '@DEDA-IRAQI',route,{...active,'activeId':'@DEDA-SALEM'}),isNull);
  });
  testWidgets('full price fits narrow 96px cell with large text', (tester) async {
    await tester.pumpWidget(MaterialApp(home:MediaQuery(
      data:const MediaQueryData(textScaler:TextScaler.linear(2)),
      child:Center(child:SizedBox(width:96,height:42,
        child:FilledButton(onPressed:(){},
          child:const DedaSixFrameButtonLabel('شراء — 1000 💎')))))));
    expect(find.text('شراء — 1000 💎'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });
}
