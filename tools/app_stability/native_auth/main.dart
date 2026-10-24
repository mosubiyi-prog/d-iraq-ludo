import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'deda_auth_session_runtime.dart';
import 'deda_pin_auth.dart';
import 'deda_session_transition_gate.dart' show DedaSessionTransitionDenied, DedaSessionTransitionBusy;

const project='demo-deda-live-progress-compat',account='07700000012',pin='583921';
const options=FirebaseOptions(apiKey:'AIzaSy000000000000000000000000000000000',
 appId:'1:1234567890:android:0000000000000000000001',messagingSenderId:'1234567890',projectId:project);
final passed=<String>[],failures=<Map<String,String>>[];
String active='bootstrap';int phase=1;
FirebaseAuth get auth=>FirebaseAuth.instance;
FirebaseFirestore get db=>FirebaseFirestore.instance;
void check(bool value){if(!value)throw StateError('native-bound-check-failed');}
Future<void> post(String path,Map<String,dynamic> body) async {
 final client=HttpClient()..connectionTimeout=const Duration(seconds:5);
 try {final request=await client.postUrl(Uri.parse('http://10.0.2.2:8766$path'));
 request.headers.contentType=ContentType.json;request.write(jsonEncode(body));
 final response=await request.close();await response.drain<void>();check(response.statusCode==200);
 } finally {client.close(force:true);}
}
Future<void> record(String name,Future<void> Function() work) async {
 active=name;await work();passed.add(name);debugPrint('BOUND_AUTH_PASS $name');
}
Future<void> reject(Future<dynamic> Function() action,bool Function(Object) accepts) async {
 try {await action();}catch(error){check(accepts(error));return;}throw StateError('expected-denial');
}
Future<void> barrier() async {
 final uid=auth.currentUser?.uid;
 await auth.authStateChanges().firstWhere((user)=>user?.uid==uid).timeout(const Duration(seconds:10));
 await Future<void>.delayed(const Duration(milliseconds:50));
}
Future<DocumentSnapshot<Map<String,dynamic>>> get(String path)=>db.doc(path).get(const GetOptions(source:Source.server));
Future<void> boundOwner() async {
 final uid=auth.currentUser!.uid;
 final session=await get('deda_sessions/$uid');final user=await get('users/$uid');
 check(session.data()?['accountKey']==account && session.data()?['installId']==await DedaPinAuth.installId());
 check(user.data()?['accountKey']==account && user.data()?['name']=='Bound Native Owner');
 check(!session.metadata.isFromCache && !user.metadata.isFromCache);
}
Future<void> first(SharedPreferences prefs) async {
 String original='';
 await post('/policy',{'mode':'merged'});
 await record('native-bound-owner-registration',() async {
  check(DedaAuthRuntime.enabled);
  await DedaPinAuth.createAccount(phone:account,fullName:'Bound Native Owner',pin:pin);
  await barrier();original=auth.currentUser!.uid;await boundOwner();
  check(await prefs.setString('qa_auth_sentinel','unchanged source'));
 });
 await record('native-bound-wrong-pin-rejected',() async {
  await DedaPinAuth.signOutFirebase();await barrier();await prefs.remove('deda_install_id_v1');
  await reject(()=>DedaPinAuth.signIn(phone:account,pin:'000000'),
   (error)=>error is StateError && error.message=='invalid-pin');
  check(auth.currentUser!.uid!=original);
  check(!(await get('deda_sessions/${auth.currentUser!.uid}')).exists);
 });
 await record('native-bound-fresh-uid-pin-profile-preserved',() async {
  final result=await DedaPinAuth.signIn(phone:account,pin:pin);await barrier();
  check(result['uid']!=original && result['name']=='Bound Native Owner');await boundOwner();
 });
 await record('native-bound-section-preserves-admin',() async {
  await DedaAuthRuntime.run<void>(kind:DedaSessionTransitionKind.adminInviteActivation,action:() async {
   await DedaAuthRuntime.createAdmin(auth,email:'bound-admin@example.invalid',password:'Synthetic-pass-123');
  });
  await barrier();final admin=auth.currentUser!.uid;check(!auth.currentUser!.isAnonymous);
  await reject(()=>DedaPinAuth.restoreTrustedSessionForAccountKey(account),
   (error)=>error is DedaSessionTransitionDenied);
  check(auth.currentUser!.uid==admin && !auth.currentUser!.isAnonymous);
 });
 await record('native-bound-explicit-owner-replaces-admin',() async {
  final before=auth.currentUser!.uid;
  await DedaPinAuth.signIn(phone:account,pin:pin);await barrier();
  check(auth.currentUser!.uid!=before && auth.currentUser!.isAnonymous);await boundOwner();
 });
 await record('native-bound-whole-flow-blocks-other-login',() async {
  final entered=Completer<void>(),hold=Completer<void>();var other=false;
  final work=DedaAuthRuntime.run<void>(kind:DedaSessionTransitionKind.ownerLogin,action:() async {
   await DedaPinAuth.signIn(phone:account,pin:pin);entered.complete();
   await DedaAuthRuntime.wait(()=>hold.future);await boundOwner();
  });
  await entered.future;final uid=auth.currentUser!.uid;
  try {
   await reject(()=>DedaAuthRuntime.run<void>(kind:DedaSessionTransitionKind.adminLogin,
    action:() async {other=true;await DedaAuthRuntime.email(auth,email:'bound-admin@example.invalid',password:'Synthetic-pass-123');}),
    (error)=>error is DedaSessionTransitionBusy);
   check(!other && auth.currentUser!.uid==uid);
  } finally {hold.complete();await work;}
 });
 await record('native-bound-timeout-keeps-sdk-lane',() async {
  final started=Completer<void>(),hold=Completer<void>();var later=false;
  final result=DedaAuthRuntime.run<void>(kind:DedaSessionTransitionKind.adminLogin,action:() async {
   await DedaAuthRuntime.controller.transition<UserCredential>(kind:DedaSessionTransitionKind.adminLogin,
    action:() async {
     // Native SDK completes, but its acknowledgement is held locally. This
     // tests uncertain completion, not a packet-level network interruption.
     final credential=await auth.signInWithEmailAndPassword(email:'bound-admin@example.invalid',password:'Synthetic-pass-123');
     started.complete();await hold.future;return credential;
    },accepts:(credential,live)=>credential.user?.uid==live.uid);
   later=true;
  });
  final outcome=reject(()=>result,(error)=>error is TimeoutException);
  await started.future;await outcome;
  await reject(()=>DedaPinAuth.signIn(phone:account,pin:pin),(error)=>error is DedaSessionTransitionBusy);
  final uid=auth.currentUser!.uid;hold.complete();
  final deadline=DateTime.now().add(const Duration(seconds:5));
  while(DedaAuthRuntime.controller.gate.diagnostics['inFlight']!=0 && DateTime.now().isBefore(deadline)) {
   await Future<void>.delayed(const Duration(milliseconds:20));
  }
  check(DedaAuthRuntime.controller.gate.diagnostics['inFlight']==0 && !later && auth.currentUser!.uid==uid);
 });
 await record('native-bound-owner-recovery-after-timeout',() async {
  await DedaPinAuth.signIn(phone:account,pin:pin);await barrier();await boundOwner();
 });
 await record('native-bound-secrets-private-no-retry',() async {
  bool denied(Object error)=>error is FirebaseException && error.code=='permission-denied';
  await reject(()=>get('deda_credentials/$account'),denied);
  await reject(()=>get('deda_auth_attempts/${auth.currentUser!.uid}'),denied);
  final snapshot=DedaAuthRuntime.capture()!;
  check(snapshot.uid==auth.currentUser!.uid && prefs.getString('qa_auth_sentinel')=='unchanged source');
 });
 await record('native-bound-cold-state-prepared',() async {
  await prefs.setString('qa_auth_uid',auth.currentUser!.uid);
  await prefs.setString('qa_auth_install',await DedaPinAuth.installId());
  await prefs.setString('qa_auth_passed',jsonEncode([...passed,active]));
  await prefs.setString('qa_auth_phase','restart-ready');
 });
 check(passed.length==10);await post('/checkpoint',{'passed':passed,'failures':failures,'phase':1});
}
Future<void> second(SharedPreferences prefs) async {
 phase=2;passed.addAll((jsonDecode(prefs.getString('qa_auth_passed')!) as List).cast<String>());
 check(passed.length==10);
 await record('cold-bound-auth-install-and-local-state',() async {
  check(auth.currentUser?.uid==prefs.getString('qa_auth_uid'));
  check(await DedaPinAuth.installId()==prefs.getString('qa_auth_install'));
  check(prefs.getString('qa_auth_sentinel')=='unchanged source');
 });
 await record('cold-bound-trusted-session-restore',() async {
  final uid=auth.currentUser!.uid;
  await DedaPinAuth.restoreTrustedSessionForAccountKey(account);await barrier();
  check(auth.currentUser!.uid==uid);await boundOwner();
 });
 await record('cold-bound-explicit-logout-preserves-local-data',() async {
  await DedaPinAuth.signOutFirebase();await barrier();
  check(auth.currentUser==null && prefs.getString('qa_auth_sentinel')=='unchanged source');
  check(DedaAuthRuntime.controller.gate.diagnostics['inFlight']==0);
 });
 check(passed.length==13);await prefs.setString('qa_auth_phase','completed');
 await post('/finish',{'passed':passed,'failures':failures,'phase':2});
}
Future<void> main() async {
 WidgetsFlutterBinding.ensureInitialized();
 FlutterError.onError=(_){failures.add({'name':'framework','code':'framework-error'});};
 PlatformDispatcher.instance.onError=(_,stack){failures.add({'name':'uncaught','code':'uncaught-error'});return true;};
 runApp(const MaterialApp(home:Scaffold(body:Text('DEDA bound auth isolated QA'))));
 try {
  check(Platform.isAndroid && project.startsWith('demo-'));
  await Firebase.initializeApp(options:options);await auth.useAuthEmulator('10.0.2.2',9099);
  db.settings=const Settings(persistenceEnabled:false);db.useFirestoreEmulator('10.0.2.2',8080);
  await auth.authStateChanges().first.timeout(const Duration(seconds:15));
  final prefs=await SharedPreferences.getInstance();await prefs.reload();
  if(prefs.getString('qa_auth_phase')=='restart-ready'){await second(prefs);}
  else {check(prefs.getString('qa_auth_phase')==null);await first(prefs);}
 } catch(error) {
  final proposed=error is FirebaseException?error.code:'case-failed';
  final code=RegExp(r'^[-a-z0-9_]{1,60}$').hasMatch(proposed)?proposed:'case-failed';
  failures.add({'name':active,'code':code});
  debugPrint('BOUND_AUTH_FAILED $active $code');
  await post('/finish',{'passed':passed,'failures':failures,'phase':phase});
 }
}
