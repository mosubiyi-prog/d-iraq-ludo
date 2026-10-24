import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:d_iraq_ludo/deda_auth_session_runtime.dart';
import 'package:d_iraq_ludo/deda_published_place_recovery.dart';
import 'package:d_iraq_ludo/deda_session_transition_gate.dart';
import 'package:d_iraq_ludo/main.dart' as app;

const account='07700000012';
class RecoveryIo implements DedaPlaceRecoveryIo {
  @override
  bool ready=true;
  @override
  DedaAuthSnapshot? principal=const DedaAuthSnapshot('new-owner',DedaSessionAuthKind.anonymous,1);
  String? install='new-install';
  DedaPlaceRecoveryDocument session=const DedaPlaceRecoveryDocument('new-owner',
    {'uid':'new-owner','accountKey':account,'installId':'new-install'});
  DedaPlaceRecoveryDocument user=const DedaPlaceRecoveryDocument('new-owner',{'accountKey':account});
  DedaPlaceRecoveryQuery query=const DedaPlaceRecoveryQuery([
    DedaPlaceRecoveryDocument('original-place',{'accountKey':account,'published':true,
      'ownerUid':'old-owner','approvalNumber':'original-approval','likes':17,'followers':9,'id':'spoofed-id'})]);
  final calls=<String>[];
  String? holdAt,failAt;
  final entered=Completer<void>(),release=Completer<void>();
  final failure=StateError('fixture-network-error');
  bool current=true;
  Future<void> before(String phase) async {
    calls.add(phase);
    if(phase==holdAt){entered.complete();await release.future;}
    if(phase==failAt)throw failure;
  }
  @override
  Future<String?> currentInstallId() async {await before('install');return install;}
  @override
  Future<DedaPlaceRecoveryDocument> readServer(String path) async {
    final phase=path.startsWith('users/')?'user':'session';
    await before(phase);return phase=='user'?user:session;
  }
  @override
  Future<DedaPlaceRecoveryQuery> publishedForAccount(String key) async {
    expect(key,account);await before('query');return query;
  }
  Future<Map<String,dynamic>?> recover() => DedaPublishedPlaceRecovery(this)
    .recover(expectedAccountKey:account,isCurrent:()=>current);
}
Matcher rejected(String code)=>isA<DedaPlaceRecoveryRejected>().having((e)=>e.code,'code',code);

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  test('new verified UID recovers canonical old place without replacing owner or engagement',() async {
    final io=RecoveryIo();final result=await io.recover();
    expect(result!['id'],'original-place');expect(result['ownerUid'],'old-owner');
    expect(result['approvalNumber'],'original-approval');expect(result['likes'],17);expect(result['followers'],9);
    expect(io.calls,['install','session','user','query']);
    expect(io.principal!.uid,'new-owner');
  });
  for(final invalid in ['', 'named-owner', '077/000']) {
    test('invalid account input is not owner proof: $invalid',() async {
      final io=RecoveryIo();
      await expectLater(DedaPublishedPlaceRecovery(io).recover(expectedAccountKey:invalid,
        isCurrent:()=>true),throwsA(rejected('owner-recovery-login-required')));
      expect(io.calls,isEmpty);
    });
  }
  for(final mode in ['not-ready','signed-out','admin']) {
    test('$mode cannot create or replace an owner session',() async {
      final io=RecoveryIo();
      if(mode=='not-ready')io.ready=false;
      if(mode=='signed-out')io.principal=null;
      if(mode=='admin')io.principal=const DedaAuthSnapshot('admin',DedaSessionAuthKind.authenticated,2);
      final before=io.principal;
      await expectLater(io.recover(),throwsA(rejected('owner-recovery-login-required')));
      expect(io.calls,isEmpty);expect(io.principal,same(before));
    });
  }
  for(final missing in [null,'']) {
    test('missing installation is not silently generated: $missing',() async {
      final io=RecoveryIo()..install=missing;
      await expectLater(io.recover(),throwsA(rejected('owner-recovery-install-required')));
      expect(io.install,missing);expect(io.calls,['install']);
    });
  }
  for(final kind in ['session','user']) {
    for(final mode in ['missing','cache','pending']) {
      test('$kind $mode is rejected before any place query',() async {
        final io=RecoveryIo();final old=kind=='session'?io.session:io.user;
        final doc=DedaPlaceRecoveryDocument(old.id,mode=='missing'?null:old.data,
          fromCache:mode=='cache',pendingWrites:mode=='pending');
        if(kind=='session'){io.session=doc;}else{io.user=doc;}
        await expectLater(io.recover(),throwsA(rejected('owner-recovery-unverified-document')));
        expect(io.calls, isNot(contains('query')));
      });
    }
  }
  for(final field in ['uid','accountKey','installId']) {
    test('session mismatch in $field cannot recover a public place',() async {
      final io=RecoveryIo();io.session=DedaPlaceRecoveryDocument('new-owner',
        {...io.session.data!,field:'other'});
      await expectLater(io.recover(),throwsA(rejected('owner-recovery-session-mismatch')));
      expect(io.calls,['install','session']);
    });
  }
  test('users proof must match the same account',() async {
    final io=RecoveryIo()..user=const DedaPlaceRecoveryDocument('new-owner',{'accountKey':'other'});
    await expectLater(io.recover(),throwsA(rejected('owner-recovery-user-mismatch')));
    expect(io.calls,['install','session','user']);
  });
  test('only authoritative server empty query means no published place',() async {
    final io=RecoveryIo()..query=const DedaPlaceRecoveryQuery([]);
    expect(await io.recover(),isNull);expect(io.calls.last,'query');
  });
  for(final mode in ['cache','pending']) {
    test('empty $mode query never becomes an editable new place',() async {
      final io=RecoveryIo()..query=DedaPlaceRecoveryQuery([],
        fromCache:mode=='cache',pendingWrites:mode=='pending');
      await expectLater(io.recover(),throwsA(rejected('owner-recovery-unverified-query')));
    });
    test('$mode published document is rejected',() async {
      final io=RecoveryIo();final old=io.query.documents.single;
      io.query=DedaPlaceRecoveryQuery([DedaPlaceRecoveryDocument(old.id,old.data,
        fromCache:mode=='cache',pendingWrites:mode=='pending')]);
      await expectLater(io.recover(),throwsA(rejected('owner-recovery-unverified-document')));
    });
  }
  test('multiple places require resolution instead of selecting the first',() async {
    final io=RecoveryIo();io.query=DedaPlaceRecoveryQuery([...io.query.documents,...io.query.documents]);
    await expectLater(io.recover(),throwsA(rejected('owner-recovery-ambiguous')));
  });
  for(final mode in ['wrong-account','unpublished','missing-id']) {
    test('$mode result cannot be adopted',() async {
      final io=RecoveryIo();final data={...io.query.documents.single.data!};
      if(mode=='wrong-account')data['accountKey']='other';
      if(mode=='unpublished')data['published']=false;
      io.query=DedaPlaceRecoveryQuery([DedaPlaceRecoveryDocument(mode=='missing-id'?'':'place',data)]);
      await expectLater(io.recover(),throwsA(rejected('owner-recovery-invalid-record')));
    });
  }
  for(final phase in ['install','session','user','query']) {
    test('$phase transport error is propagated once without an empty fallback',() async {
      final io=RecoveryIo()..failAt=phase;
      await expectLater(io.recover(),throwsA(same(io.failure)));
      expect(io.calls.where((value)=>value==phase).length,1);expect(io.calls.last,phase);
    });
    for(final change in ['intent','SDK-ABA']) {
      test('$change during $phase stops all subsequent recovery work',() async {
        final io=RecoveryIo()..holdAt=phase;
        final outcome=expectLater(io.recover(),throwsA(isA<DedaStaleSessionTransition>()));
        await io.entered.future;
        if(change=='intent'){io.current=false;}
        else{io.principal=const DedaAuthSnapshot('new-owner',DedaSessionAuthKind.anonymous,3);}
        io.release.complete();await outcome;expect(io.calls.last,phase);
      });
    }
  }
  testWidgets('busy account lane blocks the actual owner page without modifying its cache',(tester) async {
    SharedPreferences.setMockInitialValues({'deda_language_v1':'en','deda_logged_in_v1':true,
      'deda_user_name_v1':'Fixture','deda_phone_v1':account,'deda_account_phone_v1':account,
      'deda_account_type_v1':'placeOwner','sentinel':'unchanged'});
    await app.DedaPreferences.load();
    final hold=Completer<void>();
    final active=DedaAuthRuntime.run<void>(kind:DedaSessionTransitionKind.ownerLogin,action:()=>hold.future);
    try{
      await tester.pumpWidget(const MaterialApp(home:app.OwnerPlacePage()));
      await tester.pumpAndSettle();
      expect(find.text('An account operation is running. Wait for it to finish and refresh your place.'),findsOneWidget);
      final prefs=await SharedPreferences.getInstance();expect(prefs.getString('sentinel'),'unchanged');
      expect(app.DedaPreferences.phone,account);expect(tester.takeException(),isNull);
    }finally{hold.complete();await active;}
  },skip:!dedaAuthSessionRuntimeEnabled);
}
