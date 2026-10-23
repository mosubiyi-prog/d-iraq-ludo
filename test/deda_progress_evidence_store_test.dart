import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_progress_evidence_store.dart';
import 'package:d_iraq_ludo/deda_legacy_progress_capture.dart';
import 'package:d_iraq_ludo/deda_owner_session_firebase_port.dart';
import 'package:d_iraq_ludo/deda_session_flow_prototype.dart';
import 'package:d_iraq_ludo/deda_session_principal_tracker.dart';
import 'package:d_iraq_ludo/deda_session_transition_gate.dart';

const _account='07700000000';
const _id='capture_fixture_intent_0001';
const _path='deda_progress_evidence/$_account/captures/$_id';
class _Legacy implements DedaLegacyProgressReadStore {
  _Legacy(this.diamonds);
  final String diamonds;
  @override
  Future<Map<String,String?>> readStrings(List<String> keys) async => {
    keys[0]:' {"awards":{"spent":{"points":-5000}},"ledger":[{"id":"spent","points":-5000}]} ',
    keys[1]:'{"coins":17,"xp":3020,"taskClaims":["day|task"]}',keys[2]:diamonds,
  };
}
Future<DedaLegacyProgressCapture> _capture([String diamonds='{"balance":9}']) =>
  DedaLegacyProgressReader(_Legacy(diamonds)).capture(accountKey:_account,isCurrent:()=>true);
class _Io implements DedaProgressEvidenceIo {
  _Io() { user('old-device'); }
  final tracker=DedaSessionPrincipalTracker();
  @override
  bool ready=true;
  @override
  DedaFlowSdkUser? currentUser;
  String install='fixture-install';
  final docs=<String,Map<String,dynamic>>{};
  final overrides=<String,DedaOwnerServerDocument>{};
  final holds=<String,Completer<void>>{};
  final failures=<String,Object>{};
  final events=<String>[];
  int writeCount=0;
  String? listedPath;
  int? listedLimit;
  void user(String uid,{String account=_account,DedaSessionAuthKind kind=DedaSessionAuthKind.anonymous}) {
    currentUser=tracker.observe(uid,kind);
    docs['deda_sessions/$uid']={'uid':uid,'accountKey':account,'installId':install};
    docs['users/$uid']={'accountKey':account};
  }
  Future<void> visit(String event) async {
    events.add(event);
    if(holds[event]!=null)await holds[event]!.future;
    if(failures[event]!=null)throw failures[event]!;
  }
  @override
  Future<String> installId(void Function() check) async {
    await visit('install.prepare');check();return install;
  }
  @override
  Future<DedaOwnerServerDocument> readServer(String path) async {
    await visit(path.startsWith('deda_sessions/') ? 'session.read' : path.startsWith('users/') ? 'user.read' : 'evidence.read');
    return overrides[path] ?? DedaOwnerServerDocument(docs[path]);
  }
  @override
  Future<List<DedaListedProgressEvidence>> listServer(String path,{required int limit}) async {
    listedPath=path;listedLimit=limit;await visit('evidence.list');
    return [for(final entry in docs.entries.where((entry)=>entry.key.startsWith('$path/')).take(limit))
      DedaListedProgressEvidence(entry.key.split('/').last,overrides[entry.key] ?? DedaOwnerServerDocument(entry.value))];
  }
  @override
  Object serverTimestamp()=>Timestamp.fromMillisecondsSinceEpoch(1000);
  @override
  Future<void> writeOnce(String path,Map<String,dynamic> fields,void Function() check) async {
    check();await visit('transaction.read');check();
    final old=docs[path];
    if(old!=null) {
      // Simulates immutable transaction conflict semantics, not server rules.
      for(final key in ['format','kind','accountKey','sourceUid','installId','captureId']) {
        if(old[key]!=fields[key])throw const DedaProgressEvidenceConflict();
      }
      if(old['records'].toString()!=fields['records'].toString())throw const DedaProgressEvidenceConflict();
      return;
    }
    check();await visit('transaction.dispatch');
    // An already dispatched effect can complete after the UI expires.
    docs[path]=Map.of(fields);writeCount++;check();
  }
}
class _Harness {
  final io=_Io();
  bool current=true;
  late final store=DedaProgressEvidenceStore(io);
  Future<DedaStoredProgressEvidence> save(DedaLegacyProgressCapture capture,{String id=_id})=>
    store.save(captureId:id,capture:capture,isCurrent:()=>current);
  Future<DedaStoredProgressEvidence> read()=>store.read(accountKey:_account,captureId:_id,isCurrent:()=>current);
  Future<List<DedaStoredProgressEvidence>> list({int limit=20})=>store.list(accountKey:_account,isCurrent:()=>current,limit:limit);
}
Future<void> _reached(_Harness h,String event) async {
  for(var i=0;i<20 && !h.io.events.contains(event);i++) {await Future<void>.delayed(Duration.zero);}
  expect(h.io.events,contains(event));
}
void main() {
  test('save writes only immutable evidence then verifies its server readback',() async {
    final h=_Harness();final capture=await _capture();final saved=await h.save(capture);
    expect(saved.capture.raw,capture.raw);
    expect(h.io.writeCount,1);
    expect(h.io.docs[_path]!.keys.toSet(),{'format','kind','accountKey','sourceUid','installId','captureId','records','createdAt'});
    expect(h.io.docs[_path]!['kind'],'legacy-local-evidence');
    expect(h.io.events,['install.prepare','session.read','user.read','transaction.read','transaction.dispatch','evidence.read']);
  });
  test('same save intent is idempotent and never changes the first server timestamp',() async {
    final h=_Harness();final capture=await _capture();await h.save(capture);
    final timestamp=h.io.docs[_path]!['createdAt'];await h.save(capture);
    expect(h.io.writeCount,1);expect(h.io.docs[_path]!['createdAt'],timestamp);
  });
  test('new device UID and install can read original evidence without rewriting its origin',() async {
    final h=_Harness();final capture=await _capture();await h.save(capture);
    h.io.install='replacement-install';h.io.user('new-device');
    final read=await h.read();
    expect(read.sourceUid,'old-device');expect(read.installId,'fixture-install');
    expect(read.capture.raw,capture.raw);expect(h.io.writeCount,1);
  });
  test('same account history is discovered with a bounded read and immutable results',() async {
    final h=_Harness();await h.save(await _capture());
    h.io.install='replacement-install';h.io.user('new-device');
    final history=await h.list();
    expect(h.io.listedPath,'deda_progress_evidence/$_account/captures');
    expect(h.io.listedLimit,20);expect(history.single.captureId,_id);
    expect(()=>history.clear(),throwsUnsupportedError);
  });
  test('new UID cannot reuse an old intent to overwrite earlier source identity',() async {
    final h=_Harness();final capture=await _capture();await h.save(capture);
    h.io.user('new-device');
    await expectLater(h.save(capture),throwsA(isA<DedaProgressEvidenceConflict>()));
    expect(h.io.writeCount,1);
  });
  test('same capture ID with changed local content conflicts and keeps original evidence',() async {
    final h=_Harness();await h.save(await _capture());
    await expectLater(h.save(await _capture('{"balance":18}')),throwsA(isA<DedaProgressEvidenceConflict>()));
    expect(h.io.writeCount,1);
    expect((await h.read()).capture.raw[DedaLegacyProgressPart.earnedDiamonds],'{"balance":9}');
  });
  test('missing archive fails explicitly and never returns empty zero-valued progress',() async {
    final h=_Harness();await expectLater(h.read(),throwsA(isA<DedaProgressEvidenceMissing>()));
    expect(h.io.writeCount,0);
  });
  for(final metadata in ['cache','pending']) {
    test('$metadata session cannot authorize evidence access',() async {
      final h=_Harness();h.io.overrides['deda_sessions/old-device']=DedaOwnerServerDocument(
        h.io.docs['deda_sessions/old-device'],fromCache:metadata=='cache',pendingWrites:metadata=='pending');
      await expectLater(h.save(await _capture()),throwsA(isA<DedaSessionProofRejected>()));
      expect(h.io.writeCount,0);
    });
    test('$metadata archive cannot be returned as server evidence',() async {
      final h=_Harness();await h.save(await _capture());
      h.io.overrides[_path]=DedaOwnerServerDocument(h.io.docs[_path],fromCache:metadata=='cache',pendingWrites:metadata=='pending');
      await expectLater(h.read(),throwsA(isA<DedaSessionProofRejected>()));
      await expectLater(h.list(),throwsA(isA<DedaSessionProofRejected>()));
    });
  }
  for(final field in ['uid','accountKey','installId']) {
    test('mismatched owner session $field blocks evidence transaction',() async {
      final h=_Harness();h.io.docs['deda_sessions/old-device']![field]='foreign';
      await expectLater(h.save(await _capture()),throwsA(isA<DedaSessionProofRejected>()));
      expect(h.io.events,isNot(contains('transaction.read')));
    });
  }
  for(final field in ['format','kind','accountKey','captureId','createdAt','extra']) {
    test('invalid stored evidence $field is rejected without modifying it',() async {
      final h=_Harness();await h.save(await _capture());
      h.io.docs[_path]![field]=field=='format' ? 2 : 'invalid';
      await expectLater(h.read(),throwsFormatException);
      expect(h.io.writeCount,1);
    });
  }
  test('oversized UTF8 capture fails before owner lookup or any write',() async {
    final h=_Harness();final capture=await _capture('ع'*100001);
    await expectLater(h.save(capture),throwsArgumentError);expect(h.io.events,isEmpty);
  });
  for(final invalid in ['short','../other-account','']) {
    test('invalid capture ID $invalid is rejected before SDK reads',() async {
      final h=_Harness();await expectLater(h.save(await _capture(),id:invalid),throwsArgumentError);
      expect(h.io.events,isEmpty);
    });
  }
  for(final limit in [0,51]) {
    test('list limit $limit is rejected before any read',() async {
      final h=_Harness();await expectLater(h.list(limit:limit),throwsArgumentError);
      expect(h.io.events,isEmpty);
    });
  }
  for(final step in ['install.prepare','session.read','user.read','transaction.read','evidence.read','evidence.list']) {
    test('principal A B A during $step prevents late evidence publication or new dispatch',() async {
      final h=_Harness();final capture=await _capture();
      if(step=='evidence.list')await h.save(capture);
      final hold=Completer<void>();h.io.holds[step]=hold;
      final future=step=='evidence.list' ? h.list() : h.save(capture);
      final outcome=expectLater(future,throwsA(isA<DedaStaleSessionTransition>()));
      await _reached(h,step);final before=h.io.writeCount;
      h.io.user('B');h.io.user('old-device');hold.complete();await outcome;
      expect(h.io.writeCount,before);
    });
  }
  test('expired intent during transaction reread prevents dispatch',() async {
    final h=_Harness();final hold=Completer<void>();h.io.holds['transaction.read']=hold;
    final outcome=expectLater(h.save(await _capture()),throwsA(isA<DedaStaleSessionTransition>()));
    await _reached(h,'transaction.read');h.current=false;hold.complete();await outcome;
    expect(h.io.writeCount,0);
  });
  test('already dispatched save may settle after expiry but cannot read back or publish success',() async {
    final h=_Harness();final hold=Completer<void>();h.io.holds['transaction.dispatch']=hold;
    final outcome=expectLater(h.save(await _capture()),throwsA(isA<DedaStaleSessionTransition>()));
    await _reached(h,'transaction.dispatch');h.current=false;hold.complete();await outcome;
    expect(h.io.writeCount,1);expect(h.io.events,isNot(contains('evidence.read')));
  });
  test('storage write error is observed once without automatic replay or zero fallback',() async {
    final h=_Harness();final error=StateError('fixture-unavailable');h.io.failures['transaction.dispatch']=error;
    await expectLater(h.save(await _capture()),throwsA(same(error)));
    expect(h.io.events.where((e)=>e=='transaction.dispatch'),hasLength(1));expect(h.io.writeCount,0);
  });
  test('protected administration session cannot silently archive owner state',() async {
    final h=_Harness();h.io.user('admin',kind:DedaSessionAuthKind.authenticated);
    await expectLater(h.save(await _capture()),throwsA(isA<DedaStaleSessionTransition>()));
    expect(h.io.events,isEmpty);
  });
  for(final fault in ['missing','account','cache','pending']) {
    test('user proof $fault rejects before an evidence write',() async {
      final h=_Harness();
      if(fault=='missing')h.io.docs.remove('users/old-device');
      if(fault=='account')h.io.docs['users/old-device']={'accountKey':'07700000001'};
      if(fault=='cache' || fault=='pending') h.io.overrides['users/old-device']=
        DedaOwnerServerDocument(h.io.docs['users/old-device'],fromCache:fault=='cache',pendingWrites:fault=='pending');
      await expectLater(h.save(await _capture()),throwsA(isA<DedaSessionProofRejected>()));
      expect(h.io.writeCount,0);expect(h.io.events,isNot(contains('transaction.read')));
    });
  }
}
