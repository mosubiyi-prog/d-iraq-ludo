import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'deda_pin_auth.dart';
import 'deda_legacy_progress_capture.dart';
import 'deda_owner_session_firebase_port.dart';
import 'deda_progress_backup_coordinator.dart';
import 'deda_progress_backup_runtime.dart';
import 'deda_session_flow_prototype.dart';
import 'deda_session_transition_gate.dart';

// ORIGINAL, hash-verified DedaPinAuth plus real SDKs. Accounts/credentials/
// sessions/profiles/users are created by CLIENT RULES, never privileged seeds.
// Synthetic PINs, anonymous tokens, private policy diagnostics stay local.
const project='demo-deda-live-progress-compat';
const options=FirebaseOptions(apiKey:'AIzaSy000000000000000000000000000000000',
  appId:'1:1234567890:android:0000000000000000000001',
  messagingSenderId:'1234567890',projectId:project);
const originalAccount='07700000010',mergedAccount='07700000011';
const pendingId='native_pin_cold_pending_capture_00001';
const originalPin='583921',mergedPin='608314';
const raw=' {"nativePin":"original raw source","spent":-5} ';
final passed=<String>[];
final failures=<Map<String,String>>[];
String active='bootstrap';
int phase=1;
FirebaseAuth get auth=>FirebaseAuth.instance;
FirebaseFirestore get db=>FirebaseFirestore.instance;
void check(bool value){if(!value)throw StateError('native-pin-check-failed');}
bool sameValue(Object? a,Object? b) {
  if(a is Map && b is Map) {
    return a.length==b.length && a.keys.every((key)=>b.containsKey(key) && sameValue(a[key],b[key]));
  }
  if(a is List && b is List) {
    return a.length==b.length && List.generate(a.length,(i)=>sameValue(a[i],b[i])).every((v)=>v);
  }
  return a==b;
}
Future<void> post(String route,Map<String,dynamic> value) async {
  check(Platform.isAndroid);
  final client=HttpClient()..connectionTimeout=const Duration(seconds:5);
  try {
    final request=await client.postUrl(Uri.parse('http://10.0.2.2:8766$route'));
    request.headers.contentType=ContentType.json;request.write(jsonEncode(value));
    final response=await request.close();await response.drain<void>();
    check(response.statusCode==200);
  } finally {client.close(force:true);}
}
Future<void> record(String name,Future<void> Function() work) async {
  active=name;await work();passed.add(name);
  debugPrint('NATIVE_PIN_PASS $name');
}
Future<void> reject(Future<dynamic> Function() work,bool Function(Object) accepts) async {
  try {await work();}catch(error){check(accepts(error));return;}
  throw StateError('expected-rejection-missing');
}
bool denied(Object error)=>error is FirebaseException && error.code=='permission-denied';
Future<DocumentSnapshot<Map<String,dynamic>>> get(String path)=>
  db.doc(path).get(const GetOptions(source:Source.server));
Future<void> authBarrier() async {
  final uid=auth.currentUser?.uid;
  await auth.authStateChanges().firstWhere((user)=>user?.uid==uid).timeout(const Duration(seconds:10));
  // Settle queued native auth observation only; never retries authentication.
  await Future<void>.delayed(const Duration(milliseconds:50));
}
Future<void> logout() async {await DedaPinAuth.signOutFirebase();await authBarrier();check(auth.currentUser==null);}
Future<void> localSources(SharedPreferences prefs,String account) async {
  for(final key in ['deda_task_points_state_v1_$account',
    'deda_social_progress_v1_$account','deda_diamonds_wallet_v1_$account']) {
    check(await prefs.setString(key,raw));
  }
}
void sourceIntact(SharedPreferences prefs,String account) {
  for(final key in ['deda_task_points_state_v1_$account',
    'deda_social_progress_v1_$account','deda_diamonds_wallet_v1_$account']) {
    check(prefs.getString(key)==raw);
  }
}
Future<void> proof(DedaFirebaseProgressBackupDriver driver,String account) async {
  final uid=auth.currentUser!.uid,install=await DedaPinAuth.installId();
  final session=await get('deda_sessions/$uid');
  check(session.data()?['accountKey']==account && session.data()?['installId']==install);
  check(!session.metadata.isFromCache && !session.metadata.hasPendingWrites);
  check((await get('users/$uid')).data()?['accountKey']==account);
  final owner=await driver.coordinator.archive.verifyCurrentOwner(accountKey:account,isCurrent:()=>true);
  check(owner.user.uid==uid && owner.installId==install);
}

Future<void> contract(String mode,String account,String pin,SharedPreferences prefs,
    DedaFirebaseProgressBackupDriver driver) async {
  var firstUid='';
  await record('$mode-native-create-account-and-server-binding',() async {
    await prefs.remove('deda_install_id_v1');
    final result=await DedaPinAuth.createAccount(phone:account,fullName:'Synthetic Native Owner',pin:pin);
    await authBarrier();firstUid=auth.currentUser!.uid;
    check(result['uid']==firstUid && result['name']=='Synthetic Native Owner');
    check(RegExp(r'^[a-f0-9]{48}$').hasMatch(await DedaPinAuth.installId()));
    await proof(driver,account);await localSources(prefs,account);
  });
  await record('$mode-native-credential-and-attempt-private',() async {
    await reject(()=>get('deda_credentials/$account'),denied);
    await reject(()=>get('deda_auth_attempts/${auth.currentUser!.uid}'),denied);
  });
  await record('$mode-native-local-lockout-persists-and-clears',() async {
    await DedaPinAuth.clearFailedAttempts(account);
    for(var i=0;i<DedaPinAuth.maxLocalAttempts;i++){await DedaPinAuth.recordFailedAttempt(account);}
    await prefs.reload();
    final remaining=await DedaPinAuth.remainingLocalLock(account);
    check(remaining!=null && remaining>Duration.zero && remaining<=DedaPinAuth.localLockDuration);
    await DedaPinAuth.clearFailedAttempts(account);
    check(await DedaPinAuth.remainingLocalLock(account)==null);
    sourceIntact(prefs,account);
  });
  await record('$mode-native-wrong-pin-fresh-uid-denied',() async {
    await logout();await prefs.remove('deda_install_id_v1');
    await reject(()=>DedaPinAuth.signIn(phone:account,pin:'000000'),
      (error)=>error is StateError && error.message=='invalid-pin');
    await authBarrier();check(auth.currentUser!.uid!=firstUid);
    check(!(await get('deda_sessions/${auth.currentUser!.uid}')).exists);
    await reject(()=>get('deda_account_profiles/$account'),denied);
    check(await driver.coordinator.journal.read(account)==null);
    sourceIntact(prefs,account);
  });
  await record('$mode-native-untrusted-install-restore-denied',() async {
    await reject(()=>DedaPinAuth.restoreTrustedSessionForAccountKey(account),denied);
    check(!(await get('deda_sessions/${auth.currentUser!.uid}')).exists);
    check(await driver.coordinator.journal.read(account)==null);
  });
  await record('$mode-native-correct-pin-new-uid-profile-preserved',() async {
    final result=await DedaPinAuth.signIn(phone:account,pin:pin);await authBarrier();
    check(result['uid']==auth.currentUser!.uid && result['uid']!=firstUid);
    check(result['name']=='Synthetic Native Owner');await proof(driver,account);
    final profile=(await get('deda_account_profiles/$account')).data()!;
    check(profile['name']=='Synthetic Native Owner');
    check((profile['trustedInstallIds'] as List).contains(await DedaPinAuth.installId()));
    sourceIntact(prefs,account);
  });
  await record('$mode-native-trusted-restore-session-alone-insufficient-for-backup',() async {
    final before=auth.currentUser!.uid;
    await logout();final user=await DedaPinAuth.restoreTrustedSessionForAccountKey(account);
    await authBarrier();check(user.uid!=before);
    check((await get('deda_sessions/${user.uid}')).data()?['accountKey']==account);
    check((await get('deda_account_profiles/$account')).data()?['name']=='Synthetic Native Owner');
    check(!(await get('users/${user.uid}')).exists);
    await reject(()=>driver.coordinator.archive.verifyCurrentOwner(accountKey:account,isCurrent:()=>true),
      (error)=>error is DedaSessionProofRejected);
    check(await driver.coordinator.journal.read(account)==null);
  });
  await record('$mode-native-owner-adapter-completes-binding',() async {
    final uid=auth.currentUser!.uid;
    final before=(await get('deda_account_profiles/$account')).data()!;
    final flow=DedaSessionFlowPrototype(
      port:DedaOwnerSessionFirebasePort(io:driver.session,phone:account),gate:DedaSessionTransitionGate());
    final result=await flow.completeTrustedOwnerBinding(accountKey:account,
      origin:DedaSessionTransitionOrigin.userAction,isCurrent:()=>true);
    check(result.user.uid==uid && result.proof.ownerVerified && result.proof.trustedInstallation &&
      result.profile?.name=='Synthetic Native Owner');
    final after=(await get('deda_account_profiles/$account')).data()!;
    check(sameValue(before,after));
    await proof(driver,account);sourceIntact(prefs,account);
  });
}

Future<void> first(SharedPreferences prefs) async {
  final driver=DedaFirebaseProgressBackupDriver.create();
  try {
    await post('/policy',{'mode':'original'});
    await contract('original',originalAccount,originalPin,prefs,driver);
    await record('original-native-archive-scope-still-denied',() async {
      final capture=await driver.coordinator.reader.capture(accountKey:originalAccount,isCurrent:()=>true);
      await reject(()=>driver.coordinator.archive.save(captureId:'native_pin_original_denied_capture_01',
        capture:capture,isCurrent:()=>true),denied);
      check(await driver.coordinator.journal.read(originalAccount)==null);sourceIntact(prefs,originalAccount);
    });
    await logout();await post('/policy',{'mode':'merged'});
    await contract('merged',mergedAccount,mergedPin,prefs,driver);
    String captureId='',origin='',captureInstall='';
    await record('merged-native-archive-roundtrip',() async {
      check(await driver.backup(mergedAccount,()=>true));
      final rows=await driver.coordinator.archive.list(accountKey:mergedAccount,isCurrent:()=>true);
      check(rows.length==1);final row=rows.single;
      captureId=row.captureId;origin=row.sourceUid;captureInstall=row.installId;
      check(origin==auth.currentUser!.uid && row.capture.raw[DedaLegacyProgressPart.taskPoints]==raw);
      check(await driver.coordinator.journal.read(mergedAccount)==null);sourceIntact(prefs,mergedAccount);
    });
    await record('merged-native-cross-account-profile-and-evidence-denied',() async {
      await reject(()=>get('deda_account_profiles/$originalAccount'),denied);
      await reject(()=>get('deda_progress_evidence/$originalAccount/captures/$captureId'),denied);
      sourceIntact(prefs,originalAccount);sourceIntact(prefs,mergedAccount);
    });
    await record('merged-native-new-uid-reads-original-evidence',() async {
      await logout();await DedaPinAuth.signIn(phone:mergedAccount,pin:mergedPin);await authBarrier();
      check(auth.currentUser!.uid!=origin);await proof(driver,mergedAccount);
      final old=await driver.coordinator.archive.read(accountKey:mergedAccount,captureId:captureId,isCurrent:()=>true);
      check(old.sourceUid==origin && old.installId==captureInstall && old.capture.raw[DedaLegacyProgressPart.taskPoints]==raw);
      check((await driver.coordinator.archive.list(accountKey:mergedAccount,isCurrent:()=>true)).length==1);
    });
    await record('merged-native-pending-prepared-for-force-stop',() async {
      final intent=await driver.coordinator.prepare(accountKey:mergedAccount,captureId:pendingId,isCurrent:()=>true);
      check(await prefs.setString('qa_native_pin_pending',intent.encode()));
      check(await prefs.setString('qa_native_pin_uid',auth.currentUser!.uid));
      check(await prefs.setString('qa_native_pin_install',await DedaPinAuth.installId()));
    });
    check(passed.length==21 && failures.isEmpty);
    check(await prefs.setString('qa_native_pin_passed',jsonEncode(passed)));
    check(await prefs.setString('qa_native_pin_phase','restart-ready'));await prefs.reload();
    check(prefs.getString('qa_native_pin_phase')=='restart-ready');
    await post('/checkpoint',{'passed':passed,'failures':failures,'phase':1});
  } finally {await driver.dispose();}
}

Future<void> second(SharedPreferences prefs) async {
  phase=2;
  final history=jsonDecode(prefs.getString('qa_native_pin_passed')??'null');
  check(history is List && history.length==21);passed.addAll((history as List).cast<String>());
  await authBarrier();
  await record('cold-native-auth-install-and-journal-survive',() async {
    check(auth.currentUser?.uid==prefs.getString('qa_native_pin_uid'));
    check(await DedaPinAuth.installId()==prefs.getString('qa_native_pin_install'));
    final encoded=await DedaSharedPreferencesBackupJournal().read(mergedAccount);
    check(encoded!=null && encoded==prefs.getString('qa_native_pin_pending'));
    check(DedaProgressBackupIntent.decode(encoded!,mergedAccount).captureId==pendingId);
    sourceIntact(prefs,originalAccount);sourceIntact(prefs,mergedAccount);
  });
  DedaFirebaseProgressBackupDriver? driver;
  dedaProgressBackupAccount.complete(dedaProgressBackupAccount.begin(),mergedAccount);
  final runtime=DedaProgressBackupRuntime(account:dedaProgressBackupAccount,
    currentAccount:()=>mergedAccount,enabled:true,
    driverFactory:()=>driver=DedaFirebaseProgressBackupDriver.create());
  await record('cold-native-root-recovers-original-pending',() async {
    runApp(DedaProgressBackupHost.forTesting(currentAccount:()=>mergedAccount,runtime:runtime,
      child:const MaterialApp(home:Scaffold(body:Text('Native PIN isolated QA')))));
    final deadline=DateTime.now().add(const Duration(seconds:30));
    while(runtime.status!=DedaProgressBackupStatus.saved && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds:30));
    }
    check(runtime.status==DedaProgressBackupStatus.saved && driver!=null);
    final evidence=await driver!.coordinator.archive.read(accountKey:mergedAccount,captureId:pendingId,isCurrent:()=>true);
    check(evidence.sourceUid==prefs.getString('qa_native_pin_uid') && evidence.installId==prefs.getString('qa_native_pin_install'));
    check(evidence.capture.raw[DedaLegacyProgressPart.taskPoints]==raw);
    check(await driver!.coordinator.journal.read(mergedAccount)==null);sourceIntact(prefs,mergedAccount);
  });
  await record('cold-native-root-skips-unchanged-and-secrets-stay-private',() async {
    await runtime.request();check(runtime.status==DedaProgressBackupStatus.unchanged);
    check((await driver!.coordinator.archive.list(accountKey:mergedAccount,isCurrent:()=>true)).length==2);
    await reject(()=>get('deda_credentials/$mergedAccount'),denied);
    await reject(()=>get('deda_auth_attempts/${auth.currentUser!.uid}'),denied);
    sourceIntact(prefs,originalAccount);sourceIntact(prefs,mergedAccount);
  });
  await runtime.dispose();check(passed.length==24 && failures.isEmpty);
  await prefs.setString('qa_native_pin_phase','completed');
  await post('/finish',{'passed':passed,'failures':failures,'phase':2});
}
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError=(_){failures.add({'name':'framework','code':'framework-error'});};
  PlatformDispatcher.instance.onError=(_,stack){failures.add({'name':'uncaught','code':'uncaught-error'});return true;};
  runApp(const MaterialApp(home:Scaffold(body:Center(child:Text('DEDA isolated native PIN QA')))));
  try {
    check(Platform.isAndroid && project.startsWith('demo-'));
    await Firebase.initializeApp(options:options);
    await auth.useAuthEmulator('10.0.2.2',9099);
    db.settings=const Settings(persistenceEnabled:false);db.useFirestoreEmulator('10.0.2.2',8080);
    await auth.authStateChanges().first.timeout(const Duration(seconds:15));
    final prefs=await SharedPreferences.getInstance();await prefs.reload();
    if(prefs.getString('qa_native_pin_phase')=='restart-ready'){await second(prefs);}
    else {check(prefs.getString('qa_native_pin_phase')==null);await first(prefs);}
  } catch(error) {
    final proposed=error is FirebaseException?error.code:'case-failed';
    final code=RegExp(r'^[-a-z0-9_]{1,60}$').hasMatch(proposed)?proposed:'case-failed';
    failures.add({'name':active,'code':code});
    debugPrint('NATIVE_PIN_FAILED $active $code');
    await post('/finish',{'passed':passed,'failures':failures,'phase':phase});
  }
}
