import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:d_iraq_ludo/deda_progress_backup_coordinator.dart';
import 'package:d_iraq_ludo/deda_progress_evidence_store.dart';
import 'package:d_iraq_ludo/deda_legacy_progress_capture.dart';
import 'package:d_iraq_ludo/deda_owner_session_firebase_port.dart';
import 'package:d_iraq_ludo/deda_session_flow_prototype.dart';
import 'package:d_iraq_ludo/deda_session_principal_tracker.dart';
import 'package:d_iraq_ludo/deda_session_transition_gate.dart';

const account='07700000000',other='07700000001';
const captureId='capture_backup_intent_00001';
const path='deda_progress_evidence/$account/captures/$captureId';
const pendingKey='deda_progress_backup_pending_v1_$account';
class Source implements DedaLegacyProgressReadStore {
  int reads=0;
  String points=' {"awards":{"spent":-5000},"ledger":["original"]} ';
  Completer<void>? hold;
  @override
  Future<Map<String,String?>> readStrings(List<String> keys) async {
    reads++;if(hold != null) await hold!.future;
    return {keys[0]:points,keys[1]:'{"coins":17,"xp":3020}',keys[2]:null};
  }
}
class Journal implements DedaProgressBackupJournal {
  final values=<String,String>{};
  int writes=0,removes=0;
  Object? failure;
  bool refuseRemove=false;
  @override
  Future<String?> read(String accountKey) async => values[accountKey];
  @override
  Future<void> writeOnce(String accountKey,String encoded,void Function() check) async {
    check();if(failure != null)throw failure!;
    if(values[accountKey] != null && values[accountKey] != encoded)throw const DedaProgressEvidenceConflict();
    values[accountKey]=encoded;writes++;check();
  }
  @override
  Future<bool> removeIfSame(String accountKey,String encoded,void Function() check) async {
    check();if(refuseRemove || values[accountKey] != encoded)return false;
    values.remove(accountKey);removes++;check();return true;
  }
}
class Io implements DedaProgressEvidenceIo {
  Io(){user('old-device');}
  final tracker=DedaSessionPrincipalTracker();
  @override
  bool ready=true;
  @override
  DedaFlowSdkUser? currentUser;
  String install='old-install';
  final docs=<String,Map<String,dynamic>>{};
  final readEvents=<String>[];
  final holds=<String,Completer<void>>{};
  final failures=<String,Object>{};
  int writes=0;
  bool throwAfterCommit=false;
  bool cacheEvidence=false;
  void user(String uid,{String accountKey=account,DedaSessionAuthKind kind=DedaSessionAuthKind.anonymous}) {
    currentUser=tracker.observe(uid,kind);
    docs['deda_sessions/$uid']={'uid':uid,'accountKey':accountKey,'installId':install};
    docs['users/$uid']={'accountKey':accountKey};
  }
  Future<void> event(String name) async {
    readEvents.add(name);if(holds[name] != null)await holds[name]!.future;
    if(failures[name] != null)throw failures[name]!;
  }
  @override
  Future<String> installId(void Function() check) async {check();return install;}
  @override
  Future<DedaOwnerServerDocument> readServer(String path) async {
    await event(path);return DedaOwnerServerDocument(docs[path],
      fromCache:cacheEvidence && path.startsWith('deda_progress_evidence/'));
  }
  @override
  Future<List<DedaListedProgressEvidence>> listServer(String path,{required int limit}) =>
    throw StateError('list-not-part-of-backup');
  @override
  Object serverTimestamp()=>Timestamp.fromMillisecondsSinceEpoch(1000);
  @override
  Future<void> writeOnce(String path,Map<String,dynamic> fields,void Function() check) async {
    check();await event('write.dispatch');
    final existing=docs[path];
    if(existing != null && existing['records'].toString() != fields['records'].toString()) {
      throw const DedaProgressEvidenceConflict();
    }
    if(existing == null) {docs[path]=Map.of(fields);writes++;}
    if(throwAfterCommit)throw StateError('write-response-lost');
    check();
  }
}
class Harness {
  final source=Source(),journal=Journal(),io=Io();
  bool current=true;
  DedaProgressBackupCoordinator coordinator({Duration timeout=const Duration(seconds:20)}) =>
    DedaProgressBackupCoordinator(reader:DedaLegacyProgressReader(source),
      archive:DedaProgressEvidenceStore(io),journal:journal,timeout:timeout);
  late final backup=coordinator();
  Future<DedaProgressBackupIntent> prepare({String id=captureId,String key=account})=>
    backup.prepare(accountKey:key,captureId:id,isCurrent:()=>current);
  Future<DedaProgressBackupResult> upload({DedaProgressBackupCoordinator? via})=>
    (via ?? backup).uploadPending(accountKey:account,isCurrent:()=>current);
}
Future<void> reached(Io io,String event) async {
  for(var i=0;i<100 && !io.readEvents.contains(event);i++) {await Future<void>.delayed(Duration.zero);}
  expect(io.readEvents,contains(event));
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('prepare verifies account and preserves raw evidence durably before any upload',() async {
    final h=Harness();final intent=await h.prepare();
    expect(intent.capture.raw[DedaLegacyProgressPart.taskPoints],h.source.points);
    expect(h.journal.values[account],intent.encode());expect(h.io.writes,0);
    expect(h.io.readEvents,['deda_sessions/old-device','users/old-device']);
  });
  test('pending request is retained exactly when source changes or a new capture ID is proposed',() async {
    final h=Harness();final first=await h.prepare();h.source.points='newer-local-data';
    final pending=await h.prepare(id:'another_capture_intent_00001');
    expect(pending.encode(),first.encode());expect(h.source.reads,1);expect(h.journal.writes,1);
  });
  test('a recreated coordinator resumes the saved request rather than recapturing current data',() async {
    final h=Harness();final first=await h.prepare();h.source.points='later-local-state';
    final result=await h.upload(via:h.coordinator());
    expect(result.evidence.capture.encode(),first.capture.encode());expect(result.journalCleared,isTrue);
    expect(h.io.writes,1);expect(h.source.reads,1);expect(h.source.points,'later-local-state');
  });
  test('unknown write outcome keeps journal and next attempt reads server before any resubmission',() async {
    final h=Harness();await h.prepare();final original=h.journal.values[account];h.io.throwAfterCommit=true;
    await expectLater(h.upload(),throwsStateError);expect(h.journal.values[account],original);expect(h.io.writes,1);
    h.io.throwAfterCommit=false;final result=await h.upload();
    expect(result.journalCleared,isTrue);expect(h.io.writes,1);expect(h.journal.removes,1);
    expect(h.io.readEvents.where((e)=>e=='write.dispatch'),hasLength(1));
  });
  test('new UID reconciles an already committed request without rewriting original provenance',() async {
    final h=Harness();await h.prepare();h.io.throwAfterCommit=true;
    await expectLater(h.upload(),throwsStateError);h.io.throwAfterCommit=false;
    h.io.install='new-install';h.io.user('new-device');
    final result=await h.upload();expect(result.evidence.sourceUid,'old-device');
    expect(result.evidence.installId,'old-install');expect(h.io.writes,1);expect(result.journalCleared,isTrue);
  });
  test('new UID cannot relabel a missing pending archive as its own capture',() async {
    final h=Harness();await h.prepare();h.io.user('new-device');
    await expectLater(h.upload(),throwsA(isA<DedaProgressBackupOriginChanged>()));
    expect(h.journal.values[account],isNotNull);expect(h.io.writes,0);
  });
  test('same UID with changed installation also preserves an unresolved request',() async {
    final h=Harness();await h.prepare();h.io.install='new-install';h.io.user('old-device');
    await expectLater(h.upload(),throwsA(isA<DedaProgressBackupOriginChanged>()));expect(h.io.writes,0);
  });
  for(final failure in [StateError('network-failure'),const DedaSessionProofRejected()]) {
    test('failed server lookup never triggers save: ${failure.runtimeType}',() async {
      final h=Harness();await h.prepare();h.io.failures[path]=failure;
      await expectLater(h.upload(),throwsA(same(failure)));expect(h.io.writes,0);expect(h.journal.removes,0);
    });
  }
  test('cached server response cannot cause upload or retire pending evidence',() async {
    final h=Harness();await h.prepare();h.io.cacheEvidence=true;
    // Even cached absence is not an authoritative server "not found" result.
    await expectLater(h.upload(),throwsA(isA<DedaSessionProofRejected>()));
    expect(h.io.writes,0);expect(h.journal.removes,0);
  });
  for(final field in ['sourceUid','installId','records']) {
    test('conflicting remote $field keeps the local journal intact',() async {
      final h=Harness();await h.prepare();h.io.throwAfterCommit=true;await expectLater(h.upload(),throwsStateError);
      h.io.throwAfterCommit=false;
      h.io.docs[path]![field]=field=='records' ? {'taskPoints':'changed','socialCoinsAndXp':null,'earnedDiamonds':null} : 'other';
      await expectLater(h.upload(),throwsA(isA<DedaProgressEvidenceConflict>()));
      expect(h.journal.values[account],isNotNull);expect(h.journal.removes,0);
    });
  }
  test('journal cleanup refusal returns verified archive but never pretends local cleanup succeeded',() async {
    final h=Harness();await h.prepare();h.journal.refuseRemove=true;final result=await h.upload();
    expect(result.journalCleared,isFalse);expect(h.journal.values[account],isNotNull);expect(h.io.writes,1);
  });
  test('local journal save failure prevents all cloud upload',() async {
    final h=Harness();h.journal.failure=StateError('disk-failed');
    await expectLater(h.prepare(),throwsStateError);expect(h.io.writes,0);expect(h.journal.values,isEmpty);
  });
  test('empty journal is not a new account and does not archive zeros',() async {
    final h=Harness();await expectLater(h.upload(),throwsA(isA<DedaProgressEvidenceMissing>()));
    expect(h.source.reads,0);expect(h.io.writes,0);
  });
  test('corrupt pending JSON is retained without replacement',() async {
    final h=Harness();h.journal.values[account]='damaged';
    await expectLater(h.prepare(),throwsFormatException);await expectLater(h.upload(),throwsFormatException);
    expect(h.journal.values[account],'damaged');expect(h.source.reads,0);expect(h.io.writes,0);
  });
  test('a journal envelope for another account is never read as the current capture',() async {
    final h=Harness();final intent=await h.prepare();h.journal.values[other]=intent.encode();
    h.io.user('other-device',accountKey:other);
    await expectLater(h.prepare(key:other),throwsFormatException);expect(h.io.writes,0);
  });
  test('wrong current account fails before local capture or journal write',() async {
    final h=Harness();h.io.user('other-device',accountKey:other);
    await expectLater(h.prepare(),throwsA(isA<DedaSessionProofRejected>()));
    expect(h.source.reads,0);expect(h.journal.writes,0);
  });
  test('administrator session is preserved and cannot initiate an owner backup',() async {
    final h=Harness();h.io.user('admin',kind:DedaSessionAuthKind.authenticated);
    await expectLater(h.prepare(),throwsA(isA<DedaStaleSessionTransition>()));
    expect(h.io.currentUser!.uid,'admin');expect(h.io.readEvents,isEmpty);
  });
  test('A B A SDK transition during local capture prevents journaling or upload',() async {
    final h=Harness();final hold=Completer<void>();h.source.hold=hold;
    final result=expectLater(h.prepare(),throwsA(isA<DedaStaleSessionTransition>()));
    while(h.source.reads==0) {await Future<void>.delayed(Duration.zero);}
    h.io.user('B');h.io.user('old-device');hold.complete();await result;
    expect(h.journal.writes,0);expect(h.io.writes,0);
  });
  test('account-intent invalidation with same SDK user rejects late capture',() async {
    final h=Harness();final hold=Completer<void>();h.source.hold=hold;
    final result=expectLater(h.prepare(),throwsA(isA<DedaStaleSessionTransition>()));
    while(h.source.reads==0) {await Future<void>.delayed(Duration.zero);}
    h.current=false;hold.complete();await result;expect(h.journal.writes,0);
  });
  test('overlapping operations fail busy instead of replacing pending intent',() async {
    final h=Harness();final hold=Completer<void>();h.source.hold=hold;final first=h.prepare();
    while(h.source.reads==0) {await Future<void>.delayed(Duration.zero);}
    await expectLater(h.prepare(),throwsA(isA<DedaProgressBackupBusy>()));
    await expectLater(h.upload(),throwsA(isA<DedaProgressBackupBusy>()));hold.complete();await first;
  });
  test('timeout retains lane until original read settles and blocks all late writes',() async {
    final h=Harness();final hold=Completer<void>();h.source.hold=hold;
    final backup=h.coordinator(timeout:const Duration(milliseconds:30));
    await expectLater(backup.prepare(accountKey:account,captureId:captureId,isCurrent:()=>h.current),
      throwsA(isA<TimeoutException>()));
    expect(backup.busy,isTrue);
    await expectLater(backup.uploadPending(accountKey:account,isCurrent:()=>true),throwsA(isA<DedaProgressBackupBusy>()));
    hold.complete();await Future<void>.delayed(Duration.zero);
    expect(backup.busy,isFalse);expect(h.journal.writes,0);expect(h.io.writes,0);
  });
  test('a write already dispatched may commit after timeout but retains the recovery journal',() async {
    final h=Harness();await h.prepare();final hold=Completer<void>();h.io.holds['write.dispatch']=hold;
    final backup=h.coordinator(timeout:const Duration(milliseconds:30));
    final outcome=expectLater(h.upload(via:backup),throwsA(isA<TimeoutException>()));
    await reached(h.io,'write.dispatch');await outcome;expect(backup.busy,isTrue);
    hold.complete();await Future<void>.delayed(Duration.zero);
    expect(h.io.writes,1);expect(h.journal.values[account],isNotNull);expect(h.journal.removes,0);
    h.io.holds.clear();expect((await h.upload()).journalCleared,isTrue);expect(h.io.writes,1);
  });
  test('invalid capture ID fails without reading owner or local progress',() async {
    final h=Harness();await expectLater(h.prepare(id:'../escape'),throwsArgumentError);
    expect(h.io.readEvents,isEmpty);expect(h.source.reads,0);
  });
  test('invalid timeout rejects before any work starts',() {
    expect(()=>Harness().coordinator(timeout:Duration.zero),throwsArgumentError);
  });
  test('real preferences journal preserves source keys and removes only the exact archived request',() async {
    SharedPreferences.setMockInitialValues({'deda_task_points_state_v1_$account':'original',
      'deda_personal_places_v1':'private-places','deda_pin_secret':'DO-NOT-READ'});
    final journal=DedaSharedPreferencesBackupJournal();final h=Harness();final encoded=(await h.prepare()).encode();
    await journal.writeOnce(account,encoded,(){});await journal.writeOnce(account,encoded,(){});
    await expectLater(journal.writeOnce(account,'different',(){}),throwsA(isA<DedaProgressEvidenceConflict>()));
    expect(await journal.removeIfSame(account,'different',(){}),isFalse);
    expect(await journal.read(account),encoded);expect(await journal.removeIfSame(account,encoded,(){}),isTrue);
    final prefs=await SharedPreferences.getInstance();expect(prefs.containsKey(pendingKey),isFalse);
    expect(prefs.getString('deda_task_points_state_v1_$account'),'original');
    expect(prefs.getString('deda_personal_places_v1'),'private-places');
    expect(prefs.getString('deda_pin_secret'),'DO-NOT-READ');
  });
  test('real journal stale guard cannot write or remove a pending request',() async {
    SharedPreferences.setMockInitialValues({pendingKey:'retained'});
    final journal=DedaSharedPreferencesBackupJournal();
    void stale(){throw const DedaStaleSessionTransition();}
    await expectLater(journal.writeOnce(account,'replacement',stale),throwsA(isA<DedaStaleSessionTransition>()));
    await expectLater(journal.removeIfSame(account,'retained',stale),throwsA(isA<DedaStaleSessionTransition>()));
    expect(await journal.read(account),'retained');
  });
}
