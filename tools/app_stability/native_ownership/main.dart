import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'deda_pin_auth.dart';
import 'deda_backend.dart';
import 'deda_lab_frame_secure_checkout.dart';
import 'deda_owner18_frame_checkout.dart';
import 'deda_owner18_cosmetics.dart';

// Only unused purchase dependencies are stubs. Every tested ownership/PIN/
// Firestore proof method is copied from the real app and hash-recorded.
class DedaPreferences {static String phone='';}
class DedaDiamondsWallet {
  static int calls=0;
  static Future<void> load() async {calls++;throw StateError('purchase-forbidden-in-read-test');}
  static int get purchasableBalance {calls++;throw StateError('purchase-forbidden-in-read-test');}
  static Future<bool> spend(int amount) async {calls++;throw StateError('purchase-forbidden-in-read-test');}
}
const project='demo-deda-live-progress-compat';
const account='07700000020',other='07700000021',pin='593826';
const options=FirebaseOptions(apiKey:'AIzaSy000000000000000000000000000000000',appId:'1:1234567890:android:0000000000000000000001',messagingSenderId:'1234567890',projectId:project);
final passed=<String>[],failures=<Map<String,String>>[];
String active='bootstrap';
FirebaseAuth get auth=>FirebaseAuth.instance;
FirebaseFirestore get db=>FirebaseFirestore.instance;
void check(bool yes){if(!yes)throw StateError('ownership-check-failed');}
Future<void> post(String route,Map<String,dynamic> data) async {
  final c=HttpClient()..connectionTimeout=const Duration(seconds:5);
  try {final q=await c.postUrl(Uri.parse('http://10.0.2.2:8767$route'));q.headers.contentType=ContentType.json;q.write(jsonEncode(data));
    final r=await q.close();await r.drain<void>();check(r.statusCode==200);
  }finally{c.close(force:true);}
}
Future<void> record(String name,Future<void> Function() work) async {active=name;await work();passed.add(name);}
Future<void> reject(Future<dynamic> Function() work) async {try {await work();}catch(_){return;}throw StateError('rejection-missing');}
Future<void> identity(String phone,{bool createRoute=false}) async {
  final uid=auth.currentUser!.uid,id=DedaBackend.personalShareIdForPhone(phone);
  await db.doc('users/$uid').set({'sharePersonalId':id},SetOptions(merge:true));
  if(createRoute)await db.doc('deda_share_ids/$id').set({'publicId':id,'kind':'personal',
    'displayName':'Synthetic Native Owner','ownerUid':uid,'active':true,
    'createdAt':FieldValue.serverTimestamp(),'updatedAt':FieldValue.serverTimestamp()});
}
Future<void> signOut() async {await DedaPinAuth.signOutFirebase();await Future<void>.delayed(Duration.zero);}
Future<void> run() async {
  final prefs=await SharedPreferences.getInstance();String firstUid='',firstInstall='';
  final original=DedaBackend.personalShareIdForPhone(account);
  await record('native-original-pin-account-and-route-created-by-client',() async {
    await DedaPinAuth.createAccount(phone:account,fullName:'Synthetic Native Owner',pin:pin);
    DedaPreferences.phone=account;firstUid=auth.currentUser!.uid;firstInstall=await DedaPinAuth.installId();
    await identity(account,createRoute:true);
    await post('/ownership-history',{'uid':firstUid,'original':original});
  });
  await record('native-original-owner-reads-all-thirteen-frames',() async {
    final owned=await DedaLabFrameSecureCheckout.verifiedOwnedFrameIds(original);
    check(owned.length==13 && owned.containsAll(DedaLabFrameSecureCheckout.paidFrameIds));
  });
  await record('native-same-pin-new-uid-and-new-install',() async {
    await signOut();await prefs.remove('deda_install_id_v1');
    await DedaPinAuth.signIn(phone:account,pin:pin);DedaPreferences.phone=account;
    check(auth.currentUser!.uid!=firstUid && await DedaPinAuth.installId()!=firstInstall);
    await identity(account);
  });
  await record('native-new-device-recovers-existing-inventory-and-appearance',() async {
    final owned=await DedaOwner18FrameCheckout.verifiedOwnedFrameIds(original);
    check(owned.length==13 && owned.containsAll(DedaLabFrameSecureCheckout.paidFrameIds));
    check(await DedaLabFrameSecureCheckout.isOwned(originalId:original,frameId:'FRAME_03'));
    final appearance=await DedaOwner18Cosmetics.read(original);
    check(appearance['avatar']==2 && appearance['frame']==7 && appearance['background']==1);
    check((appearance['ownedStyles'] as List).contains('badge_spark'));
    check((appearance['activeBadges'] as List).contains('badge_spark'));
  });
  await record('native-other-account-cannot-read-original-ownership',() async {
    await signOut();await prefs.remove('deda_install_id_v1');
    await DedaPinAuth.createAccount(phone:other,fullName:'Synthetic Other',pin:pin);
    DedaPreferences.phone=other;await identity(other);
    await reject(()=>DedaOwner18FrameCheckout.verifiedOwnedFrameIds(original));
    await reject(()=>DedaOwner18Cosmetics.read(original));
  });
  await record('native-original-account-recovers-after-another-login',() async {
    await signOut();await prefs.remove('deda_install_id_v1');
    await DedaPinAuth.signIn(phone:account,pin:pin);DedaPreferences.phone=account;await identity(account);
    check((await DedaOwner18FrameCheckout.verifiedOwnedFrameIds(original)).length==13);
  });
  await record('native-offline-is-an-error-not-empty-ownership',() async {
    await db.disableNetwork();
    try {await reject(()=>DedaLabFrameSecureCheckout.verifiedOwnedFrameIds(original));}
    finally {await db.enableNetwork();}
    check((await DedaOwner18FrameCheckout.verifiedOwnedFrameIds(original)).length==13);
  });
  await record('native-restoration-does-not-charge-or-rewrite-history',() async {
    check(DedaDiamondsWallet.calls==0);await post('/check-unchanged',{});
  });
  check(passed.length==8 && failures.isEmpty);await post('/finish',{'passed':passed,'failures':failures});
}
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home:Scaffold(body:Center(child:Text('DEDA isolated ownership recovery QA')))));
  try {
    check(Platform.isAndroid);await Firebase.initializeApp(options:options);
    await auth.useAuthEmulator('10.0.2.2',9099);
    db.settings=const Settings(persistenceEnabled:false);db.useFirestoreEmulator('10.0.2.2',8080);
    await run();
  }catch(error){
    final code=error is FirebaseException?error.code:'case-failed';
    failures.add({'name':active,'code':RegExp(r'^[-a-z0-9_]{1,60}$').hasMatch(code)?code:'case-failed'});
    await post('/finish',{'passed':passed,'failures':failures});
  }
}
