import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'deda_legacy_progress_capture.dart';
import 'deda_legacy_purchase_evidence.dart';
import 'deda_owner_session_firebase_port.dart';
import 'deda_progress_backup_coordinator.dart';
import 'deda_progress_backup_runtime.dart';
import 'deda_progress_evidence_store.dart';
import 'deda_session_flow_prototype.dart';

// DISPOSABLE Android plugin harness. Never imported by DEDA main or packaged
// under its application ID. Emulator identities are seeded by a LOCAL fixture
// authority: no DEDA PIN, production data, role, reward or balance is exercised.
const project='demo-deda-progress-archive';
const demoOptions=FirebaseOptions(
  apiKey:'AIzaSy000000000000000000000000000000000',
  appId:'1:1234567890:android:0000000000000000000000',
  messagingSenderId:'1234567890',projectId:project);
const account='07700000000',otherAccount='07700000001';
const install='native-primary-install-v1';
const firstId='native_transport_first_capture_0001';
const restartId='native_transport_restart_capture_001';
const runtimeRestartId='native_runtime_restart_capture_0001';
const runtimeInstall='native-runtime-install-b-v1';
const purchaseOriginal='@DEDA-ABC123';
const paidJournal='deda_native_frame_pending_v1_${purchaseOriginal}_FRAME_03';
const rawPoints=' {"awards":{"spent":{"points":-5000}},"label":"تقدم محفوظ"} ';
const rawSocial='{"coins":17,"xp":3020,"taskClaims":["day|task"]}';
const rawDiamonds='{"balance":9,"day":"fixture","viewsToday":1}';
const sourcePoints='deda_task_points_state_v1_$account';
const sourceSocial='deda_social_progress_v1_$account';
const sourceDiamonds='deda_diamonds_wallet_v1_$account';
final passed=<String>[];
final failures=<String>[];
String activeCase='bootstrap';
int phase=1;

void check(bool condition,String message) {if(!condition)throw StateError(message);}
Future<void> post(String route,Map<String,dynamic> value) async {
  check(Platform.isAndroid,'Android-only fixture');
  final client=HttpClient()..connectionTimeout=const Duration(seconds:5);
  try {
    final request=await client.postUrl(Uri.parse('http://10.0.2.2:8765$route'));
    request.headers.contentType=ContentType.json;
    request.write(jsonEncode(value));
    final response=await request.close();
    final text=await utf8.decoder.bind(response).join();
    check(response.statusCode==200,'local fixture rejected $route: $text');
  } finally {client.close(force:true);}
}
Future<void> record(String name,Future<void> Function() action) async {
  activeCase=name;await action();passed.add(name);debugPrint('NATIVE_QA_PASS $name');
}
Future<Object> rejected(Future<dynamic> Function() action,bool Function(Object) accepts) async {
  try {await action();} catch(error) {if(!accepts(error))rethrow;return error;}
  throw StateError('expected rejection did not occur in $activeCase');
}
bool denied(Object error)=>error is FirebaseException && error.code=='permission-denied';
Future<void> seed(String uid,{String key=account,String installation=install,bool omitUser=false})=>
  post('/seed',{'uid':uid,'accountKey':key,'installId':installation,'omitUser':omitUser});
Future<void> source(SharedPreferences prefs) async {
  check(await prefs.setString(sourcePoints,rawPoints),'points fixture not persisted');
  check(await prefs.setString(sourceSocial,rawSocial),'social fixture not persisted');
  check(await prefs.setString(sourceDiamonds,rawDiamonds),'diamonds fixture not persisted');
}

class NativeClient {
  NativeClient(this.app,this.auth,this.firestore,this.session,this.transport);
  final FirebaseApp app;
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final DedaFirebaseOwnerSessionIo session;
  final DedaFirebaseProgressEvidenceIo transport;
  late final archive=DedaProgressEvidenceStore(transport);
  late final backup=coordinator(archive);
  late final dual=DedaProgressBackupCoordinator(reader:DedaLegacyProgressReader(DedaSharedPreferencesProgressReadStore()),
    archive:archive,journal:DedaSharedPreferencesBackupJournal(),
    purchaseReader:DedaLegacyPurchaseReader(DedaSharedPreferencesPurchaseReadStore()),
    purchaseArchive:DedaLegacyPurchaseEvidenceStore(archive),timeout:const Duration(seconds:8));
  String get uid=>auth.currentUser!.uid;
  DedaProgressBackupCoordinator coordinator(DedaProgressEvidenceStore store)=>
    DedaProgressBackupCoordinator(reader:DedaLegacyProgressReader(DedaSharedPreferencesProgressReadStore()),
      archive:store,journal:DedaSharedPreferencesBackupJournal(),timeout:const Duration(seconds:5));
  static Future<NativeClient> fromDefault({bool allowCreate=true}) async {
    final app=Firebase.app();
    final auth=FirebaseAuth.instance;
    await auth.authStateChanges().first.timeout(const Duration(seconds:15));
    if(auth.currentUser==null) {
      check(allowCreate,'default Auth did not survive restart');
      await auth.signInAnonymously();
    }
    check(auth.currentUser?.isAnonymous==true,'default principal is not anonymous');
    final store=FirebaseFirestore.instance;
    final session=DedaFirebaseOwnerSessionIo(auth:auth,firestore:store);
    return NativeClient(app,auth,store,session,DedaFirebaseProgressEvidenceIo(session:session,firestore:store));
  }
  static Future<NativeClient> connect(String name,{bool allowCreate=true}) async {
    check(project.startsWith('demo-'),'demo project is mandatory');
    final app=await Firebase.initializeApp(name:name,options:demoOptions);
    final auth=FirebaseAuth.instanceFor(app:app);
    await auth.useAuthEmulator('10.0.2.2',9099);
    final firestore=FirebaseFirestore.instanceFor(app:app);
    firestore.settings=const Settings(persistenceEnabled:false);
    firestore.useFirestoreEmulator('10.0.2.2',8080);
    await auth.authStateChanges().first.timeout(const Duration(seconds:15));
    if(auth.currentUser==null) {
      check(allowCreate,'native Auth session did not survive process restart');
      await auth.signInAnonymously();
    }
    check(auth.currentUser?.isAnonymous==true,'expected emulator anonymous SDK principal');
    final session=DedaFirebaseOwnerSessionIo(auth:auth,firestore:firestore);
    final transport=DedaFirebaseProgressEvidenceIo(session:session,firestore:firestore);
    return NativeClient(app,auth,firestore,session,transport);
  }
}

/// Deliberate lost-ack injection AFTER a real native Firestore transaction.
/// Every transport operation delegates to the unmodified real SDK transport.
class LostAckIo implements DedaProgressEvidenceIo {
  LostAckIo(this.real);
  final DedaProgressEvidenceIo real;
  int dispatches=0;
  bool armed=true;
  @override
  bool get ready=>real.ready;
  @override
  DedaFlowSdkUser? get currentUser=>real.currentUser;
  @override
  Future<String> installId(void Function() check)=>real.installId(check);
  @override
  Future<DedaOwnerServerDocument> readServer(String path)=>real.readServer(path);
  @override
  Future<List<DedaListedProgressEvidence>> listServer(String path,{required int limit})=>real.listServer(path,limit:limit);
  @override
  Object serverTimestamp()=>real.serverTimestamp();
  @override
  Future<void> writeOnce(String path,Map<String,dynamic> fields,void Function() check) async {
    dispatches++;await real.writeOnce(path,fields,check);
    if(armed){armed=false;throw StateError('native-injected-lost-ack');}
  }
}


// Native transport is real. This one-shot pause is injected AFTER a completed
// server read, to make account/lifecycle invalidation deterministic; it does
// not claim to interrupt an in-flight network packet.
class HeldReadIo extends LostAckIo {
  HeldReadIo(super.real) {armed=false;}
  bool holding=false;
  Completer<void> reached=Completer<void>(),release=Completer<void>();
  void holdNext() {holding=true;reached=Completer<void>();release=Completer<void>();}
  @override
  Future<DedaOwnerServerDocument> readServer(String path) async {
    final result=await real.readServer(path);
    if(holding) {holding=false;reached.complete();await release.future;}
    return result;
  }
}
class NativeObservedRuntime extends DedaProgressBackupRuntime {
  NativeObservedRuntime({required super.account,required super.currentAccount,
    required super.driverFactory}):super(enabled:true);
  int pendingCalls=0;
  @override
  Future<void> request() async {
    pendingCalls++;
    try {await super.request();} finally {pendingCalls--;}
  }
  bool expectBackground=false;
  final resumed=Completer<void>();
  @override
  void pause() {
    super.pause();
    if(expectBackground)unawaited(post('/lifecycle',{'state':'paused'}));
  }
  @override
  Future<void> resume() {
    final result=super.resume();
    if(expectBackground && !resumed.isCompleted)resumed.complete();
    return result;
  }
}
Future<void> until(bool Function() condition,{int seconds=25}) async {
  final deadline=DateTime.now().add(Duration(seconds:seconds));
  while(!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds:30));
  }
  check(condition(),'bounded native runtime wait expired in $activeCase');
}
String? runtimeSelection;
void selectRuntime(String? key) {
  runtimeSelection=key;
  dedaProgressBackupAccount.complete(dedaProgressBackupAccount.begin(),key);
}
Widget label()=>const MaterialApp(home:Scaffold(body:Center(child:Text('DEDA native runtime QA'))));
Future<void> detachRoot() async {
  runApp(label());await WidgetsBinding.instance.endOfFrame;
}
Future<List<QueryDocumentSnapshot<Map<String,dynamic>>>> captures(NativeClient client,String key) async =>
  (await client.firestore.collection('deda_progress_evidence/$key/captures')
    .get(const GetOptions(source:Source.server))).docs;

Future<void> nativeRuntimeFirstPhase(SharedPreferences prefs) async {
  check(dedaProgressBackupPilot,'native harness must opt in explicitly');
  final client=await NativeClient.fromDefault();
  final uid=client.uid;
  await seed(uid);selectRuntime(null);
  var factories=0;
  DedaFirebaseProgressBackupDriver? driver;
  var runtime=NativeObservedRuntime(account:dedaProgressBackupAccount,
    currentAccount:()=>runtimeSelection,driverFactory:(){factories++;return driver=DedaFirebaseProgressBackupDriver.create();});
  runApp(DedaProgressBackupHost.forTesting(currentAccount:()=>runtimeSelection,
    runtime:runtime,child:label()));
  await WidgetsBinding.instance.endOfFrame;
  await record('native-runtime-root-selection-archives-with-real-driver',() async {
    selectRuntime(account);
    await until(()=>runtime.status==DedaProgressBackupStatus.saved);
    final rows=await captures(client,account);
    final owned=rows.where((row)=>row.data()['sourceUid']==uid).toList();
    check(owned.length==1,'root did not produce exactly one owned capture');
    check(RegExp(r'^[a-f0-9]{48}$').hasMatch(owned.single.id),'runtime capture ID is not secure 24-byte hex');
    check((owned.single.data()['records'] as Map)['taskPoints']==rawPoints,'root altered source text');
    check(factories==1 && await DedaSharedPreferencesBackupJournal().read(account)==null,'root did not settle its one shared driver');
    final sidecar=await DedaLegacyPurchaseEvidenceStore(client.archive).read(accountKey:account,captureId:owned.single.id,isCurrent:()=>true);
    check(sidecar.capture.journals['FRAME_03']=='paid' && sidecar.sourceUid==uid,'default factory omitted purchase sidecar');
  });
  await record('native-runtime-unchanged-skips-upload-after-owner-proof',() async {
    final before=(await captures(client,account)).length;
    await runtime.request();
    check(runtime.status==DedaProgressBackupStatus.unchanged,'unchanged capture not suppressed');
    check((await captures(client,account)).length==before,'unchanged capture uploaded again');
    check(factories==1 && client.uid==uid,'root recreated driver or mutated Auth');
  });
  await record('native-runtime-purchase-only-change-not-skipped',() async {
    final before=(await captures(client,account)).length;
    await prefs.setString(paidJournal,'charging');await runtime.request();
    check(runtime.status==DedaProgressBackupStatus.saved,'purchase-only change suppressed by progress cache');
    final rows=await captures(client,account);check(rows.length==before+1,'purchase change did not create one new pair');
    final sidecars=await client.firestore.collection('deda_purchase_evidence/$account/captures').get(const GetOptions(source:Source.server));
    check(sidecars.docs.any((row)=>((jsonDecode((row.data()['records'] as Map)['localSnapshot'] as String) as Map)['frameJournals'] as Map)['FRAME_03']=='charging'),'changed journal missing');
    check(prefs.getString(paidJournal)=='charging','capture cleared original charging state');
    await prefs.setString(paidJournal,'paid');
  });
  await record('native-runtime-changed-source-archives-without-overwrite',() async {
    const changed=' {"awards":{"new":5,"spent":-2},"nativeRuntime":true} ';
    final before=(await captures(client,account)).length;
    await prefs.setString(sourcePoints,changed);
    await runtime.request();
    check(runtime.status==DedaProgressBackupStatus.saved,'changed capture not saved');
    final rows=await captures(client,account);
    check(rows.length==before+1,'changed source was not one new immutable capture');
    check(rows.any((row)=>row.data()['sourceUid']==uid && (row.data()['records'] as Map)['taskPoints']==changed),'changed raw text missing');
    check(prefs.getString(sourcePoints)==changed,'runtime overwrote source');
    await prefs.setString(sourcePoints,rawPoints);
  });
  await detachRoot();await runtime.dispose();selectRuntime(null);
  final held=HeldReadIo(client.transport);
  driver=DedaFirebaseProgressBackupDriver.forTesting(session:client.session,
    coordinator:client.coordinator(DedaProgressEvidenceStore(held)),dispose:() async {});
  runtime=NativeObservedRuntime(account:dedaProgressBackupAccount,
    currentAccount:()=>runtimeSelection,driverFactory:()=>driver);
  runApp(DedaProgressBackupHost.forTesting(key:const ValueKey('native-held-root'),
    currentAccount:()=>runtimeSelection,runtime:runtime,child:label()));
  await WidgetsBinding.instance.endOfFrame;
  await record('native-runtime-A-B-A-revokes-completed-server-read',() async {
    final before=(await captures(client,account)).length;
    held.holdNext();selectRuntime(account);
    await held.reached.future.timeout(const Duration(seconds:15));
    selectRuntime(otherAccount);selectRuntime(account);
    held.release.complete();
    await until(()=>!driver!.busy && runtime.pendingCalls==0);
    check((await captures(client,account)).length==before,'stale account read dispatched an upload');
    check(await DedaSharedPreferencesBackupJournal().read(account)==null,'stale account read wrote pending journal');
  });
  await record('native-runtime-Android-home-resume-revokes-held-read',() async {
    final before=(await captures(client,account)).length;
    held.holdNext();final request=runtime.request();
    await held.reached.future.timeout(const Duration(seconds:15));
    runtime.expectBackground=true;
    await post('/background-ready',{'passed':passed,'failures':failures,'phase':1});
    // Host presses Android Home, waits for the REAL lifecycle pause signal,
    // then launches this SAME native process. No simulated lifecycle here.
    await runtime.resumed.future.timeout(const Duration(seconds:45));
    runtime.expectBackground=false;held.release.complete();await request;
    check(runtime.status!=DedaProgressBackupStatus.saved,'resume revived old lifecycle intent');
    check((await captures(client,account)).length==before,'resume queued an automatic duplicate');
    check(await DedaSharedPreferencesBackupJournal().read(account)==null,'paused read wrote a journal');
  });
  await record('native-runtime-offline-retains-pending-and-explicit-resume-recovers',() async {
    await driver!.coordinator.prepare(accountKey:account,
      captureId:'native_runtime_offline_pending_0001',isCurrent:()=>true);
    final pending=await DedaSharedPreferencesBackupJournal().read(account);
    await client.firestore.disableNetwork();
    try {
      await runtime.request();
      check(runtime.status==DedaProgressBackupStatus.blocked,'offline request not blocked');
      check(await DedaSharedPreferencesBackupJournal().read(account)==pending,'offline runtime dropped pending');
    } finally {await client.firestore.enableNetwork();}
    await until(()=>!driver!.busy);
    await runtime.resume();
    check(runtime.status==DedaProgressBackupStatus.saved,'explicit resume did not settle pending');
    check(await DedaSharedPreferencesBackupJournal().read(account)==null,'runtime pending not retired');
    check(prefs.getString(sourcePoints)==rawPoints,'offline runtime changed source');
  });
  await detachRoot();await runtime.dispose();
  await record('native-runtime-production-host-constructor-default-factory',() async {
    final before=(await captures(client,account)).length;
    runApp(DedaProgressBackupHost(key:const ValueKey('native-production-host'),
      currentAccount:()=>runtimeSelection,child:label()));
    final deadline=DateTime.now().add(const Duration(seconds:25));
    var complete=false;
    while(DateTime.now().isBefore(deadline)) {
      final count=(await captures(client,account)).length;
      if(count==before+1 && await DedaSharedPreferencesBackupJournal().read(account)==null) {complete=true;break;}
      await Future<void>.delayed(const Duration(milliseconds:150));
    }
    check(complete,'real production host/default factory did not archive');
    check(client.uid==uid && client.auth.currentUser!.isAnonymous,'host mutated SDK identity');
    await detachRoot();
  });
  await record('native-runtime-B-pending-prepared-for-cold-restart',() async {
    selectRuntime(null);
    await prefs.setString('deda_install_id_v1',runtimeInstall);
    await seed(uid,key:otherAccount,installation:runtimeInstall);
    for(final key in [
      'deda_task_points_state_v1_$otherAccount',
      'deda_social_progress_v1_$otherAccount',
      'deda_diamonds_wallet_v1_$otherAccount']) {
      check(await prefs.setString(key,' {"runtimePending":"original B"} '),'B source not persisted');
    }
    final pendingDriver=DedaFirebaseProgressBackupDriver.create();
    try {
      final intent=await pendingDriver.coordinator.prepare(accountKey:otherAccount,
        captureId:runtimeRestartId,isCurrent:()=>true);
      check(await prefs.setString('qa_runtime_intent',intent.encode()),'B intent fixture not saved');
      check(await prefs.setString('qa_runtime_uid',uid),'B native UID fixture not saved');
    } finally {await pendingDriver.dispose();await prefs.setString('deda_install_id_v1',install);}
  });
  await client.session.dispose();
}

Future<void> nativeRuntimeSecondPhase(SharedPreferences prefs) async {
  final client=await NativeClient.fromDefault(allowCreate:false);
  await record('native-runtime-default-auth-and-B-journal-survive-process',() async {
    check(client.uid==prefs.getString('qa_runtime_uid'),'default native Auth UID changed across processes');
    final encoded=prefs.getString('qa_runtime_intent');
    check(encoded!=null && await DedaSharedPreferencesBackupJournal().read(otherAccount)==encoded,'B pending journal changed across processes');
    check(DedaProgressBackupIntent.decode(encoded!,otherAccount).captureId==runtimeRestartId,'B capture ID lost');
    check(prefs.getString('deda_task_points_state_v1_$otherAccount')==' {"runtimePending":"original B"} ','B source lost');
  });
  await record('native-runtime-root-recovers-original-B-pending-after-process-restart',() async {
    await prefs.setString('deda_install_id_v1',runtimeInstall);
    selectRuntime(otherAccount);
    final runtime=NativeObservedRuntime(account:dedaProgressBackupAccount,
      currentAccount:()=>runtimeSelection,driverFactory:DedaFirebaseProgressBackupDriver.create);
    runApp(DedaProgressBackupHost.forTesting(currentAccount:()=>runtimeSelection,
      runtime:runtime,child:label()));
    await until(()=>runtime.status==DedaProgressBackupStatus.saved);
    final evidence=await client.archive.read(accountKey:otherAccount,
      captureId:runtimeRestartId,isCurrent:()=>true);
    check(evidence.sourceUid==client.uid && evidence.installId==runtimeInstall,'B original provenance changed');
    check(evidence.capture.raw[DedaLegacyProgressPart.taskPoints]==' {"runtimePending":"original B"} ','B raw evidence changed');
    check(await DedaSharedPreferencesBackupJournal().read(otherAccount)==null,'B pending not retired');
    await runtime.request();
    check(runtime.status==DedaProgressBackupStatus.unchanged,'recovered intent immediately uploaded again');
    check((await captures(client,otherAccount)).length==1,'B recovery produced duplicate captures');
    check(prefs.getString(sourcePoints)==rawPoints,'B recovery changed A source');
    await detachRoot();await runtime.dispose();
    await prefs.setString('deda_install_id_v1',install);
  });
  await client.session.dispose();
}

Future<void> firstPhase(SharedPreferences prefs) async {
  check(await prefs.setString('deda_install_id_v1',install),'install not persisted');
  final client=await NativeClient.connect('qa-owner');
  await seed(client.uid);await source(prefs);
  DedaStoredProgressEvidence? original;
  await record('native-owner-proof-and-raw-roundtrip',() async {
    final intent=await client.backup.prepare(accountKey:account,captureId:firstId,isCurrent:()=>true);
    check(intent.capture.raw[DedaLegacyProgressPart.taskPoints]==rawPoints,'raw capture changed');
    check(await DedaSharedPreferencesBackupJournal().read(account)==intent.encode(),'pending was not persisted');
    final result=await client.backup.uploadPending(accountKey:account,isCurrent:()=>true);
    original=result.evidence;
    check(result.journalCleared,'pending journal not cleared');
    check(original!.createdAt.millisecondsSinceEpoch>0,'missing native server timestamp');
    check(original!.capture.raw[DedaLegacyProgressPart.taskPoints]==rawPoints,'server raw evidence changed');
    check(prefs.getString(sourcePoints)==rawPoints,'original source was modified');
  });
  await record('native-immutable-replay-preserves-server-time',() async {
    final replay=await client.archive.save(captureId:firstId,capture:original!.capture,isCurrent:()=>true);
    check(replay.createdAt==original!.createdAt,'replay changed original server timestamp');
  });
  await record('native-conflicting-capture-preserves-source',() async {
    await prefs.setString(sourcePoints,'newer local source');
    try {
      final capture=await DedaLegacyProgressReader(DedaSharedPreferencesProgressReadStore()).capture(accountKey:account,isCurrent:()=>true);
      await rejected(()=>client.archive.save(captureId:firstId,capture:capture,isCurrent:()=>true),
        (error)=>error is DedaProgressEvidenceConflict);
      check(prefs.getString(sourcePoints)=='newer local source','conflict overwrote source');
    } finally {await prefs.setString(sourcePoints,rawPoints);}
  });
  await record('native-private-read-and-write-rules',() async {
    final own=await client.firestore.doc('users/${client.uid}').get(const GetOptions(source:Source.server));
    check(own.data()?['accountKey']==account,'own users proof unavailable');
    await rejected(()=>client.firestore.doc('users/another-native-user').get(const GetOptions(source:Source.server)),denied);
    await rejected(()=>client.firestore.doc('users/${client.uid}').set({'accountKey':otherAccount}),denied);
    await rejected(()=>client.firestore.doc('deda_progress_evidence/$otherAccount/captures/$firstId')
      .get(const GetOptions(source:Source.server)),denied);
  });
  await record('native-missing-user-proof-blocks-backup',() async {
    await seed(client.uid,omitUser:true);
    try {
      await rejected(()=>client.backup.prepare(accountKey:account,captureId:'native_missing_user_capture_0001',isCurrent:()=>true),
        (error)=>error is DedaSessionProofRejected);
      check(await DedaSharedPreferencesBackupJournal().read(account)==null,'rejected owner wrote pending journal');
    } finally {await seed(client.uid);}
  });
  await record('native-offline-pending-recovery',() async {
    await client.backup.prepare(accountKey:account,captureId:'native_offline_pending_capture_001',isCurrent:()=>true);
    final pending=await DedaSharedPreferencesBackupJournal().read(account);
    await client.firestore.disableNetwork();
    try {
      await rejected(()=>client.backup.uploadPending(accountKey:account,isCurrent:()=>true),
        (error)=>error is FirebaseException || error is TimeoutException);
      check(await DedaSharedPreferencesBackupJournal().read(account)==pending,'offline attempt lost pending journal');
    } finally {await client.firestore.enableNetwork();}
    final deadline=DateTime.now().add(const Duration(seconds:15));
    while(client.backup.busy && DateTime.now().isBefore(deadline)){await Future<void>.delayed(const Duration(milliseconds:20));}
    check(!client.backup.busy,'original SDK request did not settle');
    final recovered=await client.backup.uploadPending(accountKey:account,isCurrent:()=>true);
    check(recovered.journalCleared,'online recovery did not finish');
    check(prefs.getString(sourcePoints)==rawPoints,'offline recovery changed source');
  });
  await record('native-lost-ack-read-before-resend',() async {
    final io=LostAckIo(client.transport);
    final backup=client.coordinator(DedaProgressEvidenceStore(io));
    const id='native_lost_ack_pending_capture_01';
    await backup.prepare(accountKey:account,captureId:id,isCurrent:()=>true);
    final pending=await DedaSharedPreferencesBackupJournal().read(account);
    await rejected(()=>backup.uploadPending(accountKey:account,isCurrent:()=>true),
      (error)=>error is StateError && error.message=='native-injected-lost-ack');
    check(await DedaSharedPreferencesBackupJournal().read(account)==pending,'lost acknowledgement dropped pending');
    final stored=await client.archive.read(accountKey:account,captureId:id,isCurrent:()=>true);
    final recovered=await backup.uploadPending(accountKey:account,isCurrent:()=>true);
    check(io.dispatches==1,'uncertain write was resubmitted');
    check(recovered.evidence.createdAt==stored.createdAt,'recovery replaced earlier timestamp');
    check(recovered.journalCleared,'recovery did not retire matching pending entry');
  });
  await record('native-new-uid-reads-original-provenance',() async {
    await prefs.setString('deda_install_id_v1','native-replacement-install-v1');
    try {
      final replacement=await NativeClient.connect('qa-replacement-reader');
      check(replacement.uid!=client.uid,'replacement UID did not change');
      await seed(replacement.uid,installation:'native-replacement-install-v1');
      final old=await replacement.archive.read(accountKey:account,captureId:firstId,isCurrent:()=>true);
      check(old.sourceUid==client.uid && old.installId==install,'original provenance changed');
      final rows=await replacement.archive.list(accountKey:account,isCurrent:()=>true);
      check(rows.any((row)=>row.captureId==firstId),'replacement cannot discover original archive');
    } finally {await prefs.setString('deda_install_id_v1',install);}
  });
  await record('native-new-uid-missing-origin-remains-pending',() async {
    const id='native_old_origin_missing_capture_001';
    await client.backup.prepare(accountKey:account,captureId:id,isCurrent:()=>true);
    final pending=await DedaSharedPreferencesBackupJournal().read(account);
    await prefs.setString('deda_install_id_v1','native-replacement-install-v2');
    try {
      final replacement=await NativeClient.connect('qa-replacement-writer');
      await seed(replacement.uid,installation:'native-replacement-install-v2');
      await rejected(()=>replacement.backup.uploadPending(accountKey:account,isCurrent:()=>true),
        (error)=>error is DedaProgressBackupOriginChanged);
      check(await DedaSharedPreferencesBackupJournal().read(account)==pending,'new UID lost old pending');
      final remote=await replacement.firestore.doc('deda_progress_evidence/$account/captures/$id').get(const GetOptions(source:Source.server));
      check(!remote.exists,'new UID relabelled old pending as a fresh capture');
    } finally {await prefs.setString('deda_install_id_v1',install);}
    await client.backup.uploadPending(accountKey:account,isCurrent:()=>true);
  });
  await record('native-purchase-reader-keeps-typed-values-and-original-journals',() async {
    await prefs.setString(paidJournal,'paid');
    await prefs.setString('deda_native_frame_pending_v1_${purchaseOriginal}_FRAME_05','charging');
    await prefs.setBool('deda_native_frame_pending_v1_${purchaseOriginal}_FRAME_06',true);
    await prefs.setString('deda_style_inventory_v1_$account',' {"owned":["frame_3"]} ');
    final capture=await DedaLegacyPurchaseReader(DedaSharedPreferencesPurchaseReadStore()).capture(accountKey:account,
      originalId:purchaseOriginal,isCurrent:()=>true);
    check(capture.journals['FRAME_03']=='paid' && capture.journals['FRAME_05']=='charging' && capture.journals['FRAME_06']==true,'native types changed');
    check(prefs.getString(paidJournal)=='paid' && capture.inventory==' {"owned":["frame_3"]} ','reader altered source');
  });
  await nativeRuntimeFirstPhase(prefs);
  await record('native-pending-journal-prepared-for-cold-restart',() async {
    final intent=await client.dual.prepare(accountKey:account,captureId:restartId,isCurrent:()=>true);
    check(await prefs.setString('qa_restart_intent',intent.encode()),'restart intent not saved');
    check(await prefs.setString('qa_owner_uid',client.uid),'restart UID not saved');
    check(intent.capture.raw[DedaLegacyProgressPart.taskPoints]==rawPoints,'restart source changed');
    check(intent.purchaseCaptureObserved && intent.purchaseCapture?.journals['FRAME_03']=='paid','restart journal omitted purchase snapshot');
  });
  check(passed.length==20 && failures.isEmpty,'first phase incomplete');
  check(await prefs.setString('qa_passed',jsonEncode(passed)),'pass history not persisted');
  check(await prefs.setString('qa_phase','restart-ready'),'restart marker not persisted');
  await prefs.reload();
  check(prefs.getString('qa_phase')=='restart-ready','native reload lost marker');
  await post('/checkpoint',{'passed':passed,'failures':failures,'phase':1,
    'scope':'native plugins with seeded sessions, not DEDA PIN or two phones'});
}

Future<void> secondPhase(SharedPreferences prefs) async {
  phase=2;
  final previous=jsonDecode(prefs.getString('qa_passed') ?? 'null');
  check(previous is List && previous.length==20,'first process pass history did not survive');
  passed.addAll((previous as List).cast<String>());
  await record('native-preferences-and-pending-survive-process-restart',() async {
    final encoded=prefs.getString('qa_restart_intent');
    check(encoded!=null,'pending source missing after restart');
    final intent=DedaProgressBackupIntent.decode(encoded!,account);
    check(intent.captureId==restartId,'restart capture ID changed');
    check(await DedaSharedPreferencesBackupJournal().read(account)==encoded,'native journal did not survive');
    check(intent.purchaseCaptureObserved && intent.purchaseCapture?.journals['FRAME_03']=='paid','purchase payload lost across cold restart');
    check(prefs.getString(sourcePoints)==rawPoints && prefs.getString(sourceSocial)==rawSocial &&
      prefs.getString(sourceDiamonds)==rawDiamonds,'native source records changed or disappeared');
  });
  await record('native-auth-owner-and-pending-upload-after-restart',() async {
    final client=await NativeClient.connect('qa-owner',allowCreate:false);
    check(client.uid==prefs.getString('qa_owner_uid'),'Auth UID did not persist across process restart');
    final result=await client.dual.uploadPending(accountKey:account,isCurrent:()=>true);
    check(result.journalCleared && result.evidence.captureId==restartId,'pending recovery incomplete');
    check(result.evidence.sourceUid==client.uid && result.evidence.installId==install,'pending provenance changed');
    check(result.evidence.capture.raw[DedaLegacyProgressPart.taskPoints]==rawPoints,'recovered raw source changed');
    check(prefs.getString(sourcePoints)==rawPoints,'recovery overwrote source preferences');
    check(result.purchaseEvidence?.capture.journals['FRAME_03']=='paid' && prefs.getString(paidJournal)=='paid','cold recovery omitted sidecar or changed paid marker');
  });
  await nativeRuntimeSecondPhase(prefs);
  check(passed.length==24 && failures.isEmpty,'second phase incomplete');
  await prefs.setString('qa_phase','completed');
  await post('/finish',{'passed':passed,'failures':failures,'phase':2,
    'coldRestart':true,'nativeAuthUidPersisted':true,'runtimeHostTested':true,
    'actualAndroidBackgroundResume':true,'runtimeDefaultFactoryTested':true,
    'scope':'demo native transport and passive runtime harness; seeded sessions, not DEDA PIN'});
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError=(details){failures.add('framework: ${details.exceptionAsString()}');FlutterError.presentError(details);};
  PlatformDispatcher.instance.onError=(error,stack){failures.add('unhandled: $error');return false;};
  runApp(const MaterialApp(home:Scaffold(body:Center(child:Text('DEDA isolated native transport QA')))));
  try {
    // This pinned Firestore platform interface bootstraps its singleton through
    // Firebase.app() even when instanceFor is used with a named application.
    // DEDA already initializes DEFAULT; the standalone harness must do so too.
    final defaultApp=await Firebase.initializeApp(options:demoOptions);
    await FirebaseAuth.instanceFor(app:defaultApp).useAuthEmulator('10.0.2.2',9099);
    final defaultStore=FirebaseFirestore.instanceFor(app:defaultApp);
    defaultStore.settings=const Settings(persistenceEnabled:false);
    defaultStore.useFirestoreEmulator('10.0.2.2',8080);
    final prefs=await SharedPreferences.getInstance();await prefs.reload();
    final marker=prefs.getString('qa_phase');
    if(marker=='restart-ready'){await secondPhase(prefs);}
    else {check(marker==null,'unexpected stale harness data');await firstPhase(prefs);}
  } catch(error,stack) {
    failures.add('$activeCase: $error\n${stack.toString().split('\n').take(8).join('\n')}');
    debugPrint('NATIVE_QA_FAILED $activeCase: $error');
    await post('/finish',{'passed':passed,'failures':failures,'phase':phase});
  }
}
