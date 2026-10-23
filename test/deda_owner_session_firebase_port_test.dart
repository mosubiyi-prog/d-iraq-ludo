import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_owner_session_firebase_port.dart';
import 'package:d_iraq_ludo/deda_session_flow_prototype.dart';
import 'package:d_iraq_ludo/deda_session_principal_tracker.dart';
import 'package:d_iraq_ludo/deda_session_transition_gate.dart';

const _phone = ' 0770 000 0000 ';
const _account = '07700000000';
const _explicit = DedaSessionTransitionOrigin.userAction;
class _Union { const _Union(this.values); final List<String> values; }
class _Write {
  const _Write(this.path, this.fields, this.merge);
  final String path;
  final Map<String, dynamic> fields;
  final bool merge;
}
class _Io implements DedaOwnerSessionIo {
  _Io() {
    docs['deda_account_profiles/$_account'] = {
      'accountKey': _account, 'name': ' Fixture Owner ',
      'trustedInstallIds': ['fixture-install'],
    };
  }
  final tracker = DedaSessionPrincipalTracker();
  @override
  bool ready = true;
  @override
  DedaFlowSdkUser? currentUser;
  final docs = <String, Map<String, dynamic>>{};
  final overrides = <String, DedaOwnerServerDocument>{};
  final events = <String>[];
  final writes = <_Write>[];
  final holds = <String, Completer<void>>{};
  final failures = <String, Object>{};
  String install = 'fixture-install';
  String? remembered;
  DedaFlowSdkUser? user(String? uid, [DedaSessionAuthKind kind = DedaSessionAuthKind.anonymous]) =>
    currentUser = tracker.observe(uid, kind);
  Future<void> visit(String event) async {
    events.add(event);
    if (holds[event] != null) await holds[event]!.future;
    if (failures[event] != null) throw failures[event]!;
  }
  @override
  Future<DedaFlowSdkUser> signInAnonymous() async {
    await visit('sdk.anonymous');
    return user('fixture-sdk')!;
  }
  @override
  Future<void> signOut() async { await visit('sdk.signOut'); user(null); }
  @override
  Future<DedaOwnerServerDocument> readServer(String path) async {
    await visit('read:$path');
    return overrides[path] ?? DedaOwnerServerDocument(docs[path]);
  }
  @override
  Future<void> setDocument(String path, Map<String, dynamic> fields, {bool merge = false}) async {
    writes.add(_Write(path, Map.of(fields), merge));
    await visit('write:$path');
    final next = merge ? Map<String, dynamic>.of(docs[path] ?? {}) : <String, dynamic>{};
    for (final entry in fields.entries) {
      final value = entry.value;
      next[entry.key] = value is _Union
        ? {...?(next[entry.key] as List?), ...value.values}.toList() : value;
    }
    docs[path] = next;
  }
  @override
  Object serverTimestamp() => 'fixture-server-timestamp';
  @override
  Object arrayUnion(List<String> values) => _Union(values);
  @override
  Future<String> installId(void Function() checkCurrent) async {
    await visit('install.prepare');
    checkCurrent();
    events.add('install.value');
    return install;
  }
  @override
  Future<void> rememberKnownPhone(String phone, void Function() checkCurrent) async {
    await visit('remember.prepare');
    checkCurrent();
    remembered = phone;
    events.add('remember.write');
  }
}
class _Harness {
  _Harness({bool shortWait = false}) {
    port = DedaOwnerSessionFirebasePort(io: io, phone: _phone);
    gate = DedaSessionTransitionGate(timeout: Duration(milliseconds: shortWait ? 50 : 12000));
    flow = DedaSessionFlowPrototype(port: port, gate: gate);
  }
  final io = _Io();
  late final DedaOwnerSessionFirebasePort port;
  late final DedaSessionTransitionGate gate;
  late final DedaSessionFlowPrototype flow;
  Future<DedaOwnerFlowResult> login({String account = _account}) => flow.ownerLogin(
    accountKey: account, pin: '123456', origin: _explicit, isCurrent: () => true);
  Future<DedaOwnerFlowResult> restore() => flow.restoreOwner(
    accountKey: _account, origin: _explicit, isCurrent: () => true);
  Completer<void> hold(String event) => io.holds[event] = Completer<void>();
}
Future<void> _reached(_Harness h, String event) async {
  for (var i = 0; i < 20 && !h.io.events.contains(event); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(h.io.events, contains(event));
}

class _SdkUser implements User {
  _SdkUser(this.uid, this.isAnonymous);
  @override
  final String uid;
  @override
  final bool isAnonymous;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class _Auth implements FirebaseAuth {
  @override
  User? currentUser;
  final changes = StreamController<User?>.broadcast(sync: true);
  @override
  Stream<User?> authStateChanges() => changes.stream;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class _Metadata implements SnapshotMetadata {
  @override
  bool get hasPendingWrites => false;
  @override
  bool get isFromCache => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class _Document implements DocumentSnapshot<Map<String,dynamic>> {
  @override
  bool get exists => true;
  @override
  SnapshotMetadata get metadata => _Metadata();
  @override
  Map<String,dynamic> data() => {'fixture':'server'};
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class _Reference implements DocumentReference<Map<String,dynamic>> {
  GetOptions? readOptions;
  SetOptions? writeOptions;
  Map<String,dynamic>? written;
  @override
  Future<DocumentSnapshot<Map<String,dynamic>>> get([GetOptions? options]) async {
    readOptions = options;
    return _Document();
  }
  @override
  Future<void> set(Map<String,dynamic> data,[SetOptions? options]) async {
    written = data;
    writeOptions = options;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class _Firestore implements FirebaseFirestore {
  final reference = _Reference();
  String? requestedPath;
  @override
  DocumentReference<Map<String,dynamic>> doc(String path) {
    requestedPath = path;
    return reference;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('real Firestore transport requests server-only source and exposes metadata', () async {
    final auth = _Auth();
    final firestore = _Firestore();
    final io = DedaFirebaseOwnerSessionIo(auth:auth,firestore:firestore);
    final result = await io.readServer('deda_sessions/fixture');
    expect(firestore.requestedPath,'deda_sessions/fixture');
    expect(firestore.reference.readOptions!.source,Source.server);
    expect(result.data,{'fixture':'server'});
    expect(result.fromCache,isFalse);
    expect(result.pendingWrites,isFalse);
    await io.dispose();
    await auth.changes.close();
  });
  test('real Firestore transport preserves overwrite and merge options', () async {
    final auth = _Auth();
    final firestore = _Firestore();
    final io = DedaFirebaseOwnerSessionIo(auth:auth,firestore:firestore);
    await io.setDocument('deda_sessions/fixture',{'accountKey':_account});
    expect(firestore.reference.writeOptions!.merge,isFalse);
    await io.setDocument('users/fixture',{'name':'Fixture'},merge:true);
    expect(firestore.reference.writeOptions!.merge,isTrue);
    expect(firestore.reference.written,{'name':'Fixture'});
    await io.dispose();
    await auth.changes.close();
  });
  test('real transport preserves and reuses the existing installation preference', () async {
    SharedPreferences.setMockInitialValues({'deda_install_id_v1':' existing-install '});
    final auth = _Auth();
    final io = DedaFirebaseOwnerSessionIo(auth:auth,firestore:_Firestore());
    expect(await io.installId(() {}), 'existing-install');
    expect((await SharedPreferences.getInstance()).getString('deda_install_id_v1'),' existing-install ');
    await io.dispose();
    await auth.changes.close();
  });
  test('real transport creates one random installation id and remembers normalized phone', () async {
    SharedPreferences.setMockInitialValues({});
    final auth = _Auth();
    final io = DedaFirebaseOwnerSessionIo(auth:auth,firestore:_Firestore());
    final install = await io.installId(() {});
    expect(RegExp(r'^[0-9a-f]{48}$').hasMatch(install),isTrue);
    expect(await io.installId(() {}),install);
    await io.rememberKnownPhone(_phone, () {});
    expect((await SharedPreferences.getInstance()).getBool('deda_known_account_$_account'),isTrue);
    await io.dispose();
    await auth.changes.close();
  });
  test('real preference helpers honor expired guard before dispatching local writes', () async {
    SharedPreferences.setMockInitialValues({});
    final auth = _Auth();
    final io = DedaFirebaseOwnerSessionIo(auth:auth,firestore:_Firestore());
    void expired() => throw const DedaStaleSessionTransition();
    await expectLater(io.installId(expired),throwsA(isA<DedaStaleSessionTransition>()));
    await expectLater(io.rememberKnownPhone(_phone,expired),throwsA(isA<DedaStaleSessionTransition>()));
    expect((await SharedPreferences.getInstance()).getKeys(),isEmpty);
    await io.dispose();
    await auth.changes.close();
  });
  test('real auth observer records intermediate A B A events and ignores repeated current UID', () async {
    final auth = _Auth()..currentUser = _SdkUser('A',true);
    final io = DedaFirebaseOwnerSessionIo(auth:auth,firestore:_Firestore());
    final first = io.currentUser!;
    auth.changes.add(auth.currentUser);
    expect(io.currentUser!.revision,first.revision);
    auth.currentUser = _SdkUser('B',false);
    auth.changes.add(auth.currentUser);
    auth.currentUser = _SdkUser('A',true);
    auth.changes.add(auth.currentUser);
    expect(io.currentUser!.revision,greaterThan(first.revision));
    await io.dispose();
    await auth.changes.close();
  });

  test('tracker ignores duplicate SDK observations without invalidating expected login', () {
    final tracker = DedaSessionPrincipalTracker();
    final first = tracker.observe('A', DedaSessionAuthKind.anonymous)!;
    expect(tracker.observe('A', first.kind)!.revision, first.revision);
  });
  test('tracker observes A B A even when final UID is unchanged', () {
    final tracker = DedaSessionPrincipalTracker();
    final first = tracker.observe('A', DedaSessionAuthKind.anonymous)!;
    tracker.observe('B', DedaSessionAuthKind.authenticated);
    expect(tracker.observe('A', first.kind)!.revision, greaterThan(first.revision));
  });
  test('tracker distinguishes kind change and signout for the same UID', () {
    final tracker = DedaSessionPrincipalTracker();
    final first = tracker.observe('A', DedaSessionAuthKind.anonymous)!;
    final admin = tracker.observe('A', DedaSessionAuthKind.authenticated)!;
    expect(admin.revision, greaterThan(first.revision));
    expect(tracker.observe(null, DedaSessionAuthKind.none), isNull);
    expect(tracker.observe('A', admin.kind)!.revision, greaterThan(admin.revision));
  });

  test('owner adapter preserves exact existing write fields and merge policy', () async {
    final h = _Harness();
    final result = await h.login();
    expect(result.profile!.name, 'Fixture Owner');
    expect(result.profile!.phone, _phone.trim());
    expect(result.profile!.accountType, 'user');
    expect(h.io.remembered, _phone);
    expect(h.io.writes.map((w) => w.path), [
      'deda_auth_attempts/fixture-sdk','deda_sessions/fixture-sdk',
      'deda_account_profiles/$_account','users/fixture-sdk']);
    expect(h.io.writes.map((w) => w.merge), [false,false,true,true]);
    expect(h.io.writes[0].fields.keys.toSet(), {'uid','accountKey','pin','createdAt'});
    expect(h.io.writes[1].fields.keys.toSet(), {'uid','accountKey','installId','signedInAt','lastSeenAt'});
    expect(h.io.writes[2].fields.keys.toSet(), {'trustedInstallIds','lastSeenAt','updatedAt'});
    expect(h.io.writes[3].fields.keys.toSet(), {'name','phone','accountKey','accountType',
      'authMethod','trustedInstallIds','updatedAt','lastSeenAt'});
    expect(h.io.writes[3].fields['authMethod'], 'deda_pin_firestore_v1');
    expect(h.io.writes[2].fields['trustedInstallIds'], isA<_Union>());
    expect(h.io.events.where((e) => e.startsWith('read:')), [
      'read:deda_sessions/fixture-sdk', 'read:deda_account_profiles/$_account']);
    expect(h.io.events.any((e) => e.startsWith('read:deda_auth_attempts/')), isFalse);
    h.gate.dispose();
  });
  test('profile is bound by server session and document key without stored uid field', () async {
    final h = _Harness();
    h.io.docs['deda_account_profiles/$_account']!['phone'] = 'stored-phone';
    h.io.docs['deda_account_profiles/$_account']!['accountType'] = 'existing-type';
    final result = await h.login();
    expect(result.profile!.uid, 'fixture-sdk');
    expect(result.profile!.phone, 'stored-phone');
    expect(result.profile!.accountType, 'existing-type');
    expect(h.io.docs['deda_account_profiles/$_account'], isNot(contains('uid')));
    h.gate.dispose();
  });
  test('trusted restore checks server install membership without PIN or profile writes', () async {
    final h = _Harness();
    final result = await h.restore();
    expect(result.proof.trustedInstallation, isTrue);
    expect(h.io.writes.map((w) => w.path), ['deda_sessions/fixture-sdk']);
    expect(h.io.events.where((e) => e.startsWith('read:')), [
      'read:deda_sessions/fixture-sdk', 'read:deda_account_profiles/$_account']);
    expect(h.io.remembered, isNull);
    h.gate.dispose();
  });
  test('PIN login may trust a new install only after server proof and profile read', () async {
    final h = _Harness();
    h.io.docs['deda_account_profiles/$_account']!['trustedInstallIds'] = [];
    final result = await h.login();
    expect(result.proof.trustedInstallation, isFalse);
    expect(h.io.docs['deda_account_profiles/$_account']!['trustedInstallIds'], ['fixture-install']);
    h.gate.dispose();
  });
  test('server session alone cannot claim a trusted restore on an untrusted install', () async {
    final h = _Harness();
    h.io.docs['deda_account_profiles/$_account']!['trustedInstallIds'] = ['other-install'];
    await expectLater(h.restore(), throwsA(isA<DedaSessionProofRejected>()));
    expect(h.io.writes, hasLength(1));
    h.gate.dispose();
  });
  for (final invalid in ['missing','cache','pending','uid','account','install']) {
    test('server session readback rejects $invalid before profile or following writes', () async {
      final h = _Harness();
      final data = <String, dynamic>{'uid':'fixture-sdk','accountKey':_account,'installId':'fixture-install'};
      if (invalid == 'uid') data['uid'] = 'other';
      if (invalid == 'account') data['accountKey'] = 'other';
      if (invalid == 'install') data['installId'] = 'other';
      h.io.overrides['deda_sessions/fixture-sdk'] = DedaOwnerServerDocument(
        invalid == 'missing' ? null : data, fromCache: invalid == 'cache', pendingWrites: invalid == 'pending');
      await expectLater(h.login(), throwsA(isA<DedaSessionProofRejected>()));
      expect(h.io.events, isNot(contains('read:deda_account_profiles/$_account')));
      expect(h.io.writes, hasLength(2));
      expect(h.io.remembered, isNull);
      h.gate.dispose();
    });
  }
  for (final invalid in ['missing','cache','pending','account','name']) {
    test('server owner profile rejects $invalid before trusting a device', () async {
      final h = _Harness();
      final data = <String,dynamic>{'accountKey':_account,'name':'Fixture'};
      if (invalid == 'account') data['accountKey'] = 'other';
      if (invalid == 'name') data['name'] = ' ';
      h.io.overrides['deda_account_profiles/$_account'] = DedaOwnerServerDocument(
        invalid == 'missing' ? null : data, fromCache: invalid == 'cache', pendingWrites: invalid == 'pending');
      await expectLater(h.login(), throwsA(invalid == 'name' ? isA<StateError>() : isA<DedaSessionProofRejected>()));
      expect(h.io.writes, hasLength(2));
      h.gate.dispose();
    });
  }
  test('PIN permission-denied retains existing invalid-pin policy without reading credentials', () async {
    final h = _Harness();
    h.io.failures['write:deda_auth_attempts/fixture-sdk'] = FirebaseException(plugin:'cloud_firestore',code:'permission-denied');
    await expectLater(h.login(), throwsA(isA<StateError>().having((e) => e.message,'message','invalid-pin')));
    expect(h.io.writes, hasLength(1));
    expect(h.io.events.any((e) => e.startsWith('read:')), isFalse);
    h.gate.dispose();
  });
  test('completed transient write failure propagates once without read retries', () async {
    final h = _Harness();
    final error = FirebaseException(plugin:'cloud_firestore',code:'unavailable');
    h.io.failures['write:deda_sessions/fixture-sdk'] = error;
    await expectLater(h.login(), throwsA(same(error)));
    expect(h.io.events.where((e) => e == 'write:deda_sessions/fixture-sdk'), hasLength(1));
    expect(h.io.events, isNot(contains('sdk.signOut')));
    h.gate.dispose();
  });
  for (final wait in ['sdk.anonymous','write:deda_sessions/fixture-sdk','read:deda_sessions/fixture-sdk']) {
    test('timeout at $wait retains original barrier and prevents later owner effects', () async {
      final h = _Harness(shortWait:true);
      final hold = h.hold(wait);
      await expectLater(h.login(), throwsA(isA<TimeoutException>()));
      await expectLater(h.login(), throwsA(isA<DedaSessionTransitionBusy>()));
      final eventCount = h.io.events.length;
      hold.complete();
      await Future<void>.delayed(Duration.zero);
      expect(h.io.events, hasLength(eventCount));
      expect(h.io.remembered, isNull);
      expect(h.gate.diagnostics['inFlight'], 0);
      expect(h.gate.diagnostics['succeeded'], 0);
      h.gate.dispose();
    });
  }
  for (final wait in ['install.prepare','remember.prepare']) {
    test('changed SDK during $wait blocks nested local and server writes', () async {
      final h = _Harness();
      final hold = h.hold(wait);
      final result = h.login();
      final outcome = expectLater(result, throwsA(isA<DedaStaleSessionTransition>()));
      await _reached(h,wait);
      final before = h.io.writes.length;
      h.io.user('newer',DedaSessionAuthKind.authenticated);
      hold.complete();
      await outcome;
      expect(h.io.writes,hasLength(before));
      expect(h.io.events, isNot(contains(wait == 'install.prepare' ? 'install.value' : 'remember.write')));
      expect(h.io.remembered,isNull);
      h.gate.dispose();
    });
  }
  test('owner port refuses account binding mismatch before PIN or session writes', () async {
    final h = _Harness();
    await expectLater(h.login(account:'other'), throwsArgumentError);
    expect(h.io.writes,isEmpty);
    h.gate.dispose();
  });
  test('owner-only port rejects admin login before any SDK call', () async {
    final h = _Harness();
    await expectLater(h.flow.adminLogin(email:'fixture@example.invalid',password:'fixture',
      origin:_explicit,isCurrent:()=>true),throwsUnsupportedError);
    expect(h.io.events,isEmpty);
    h.gate.dispose();
  });
  test('active-section restore preserves a protected admin SDK session', () async {
    final h = _Harness();
    final admin = h.io.user('protected',DedaSessionAuthKind.authenticated);
    await expectLater(h.flow.restoreOwner(accountKey:_account,
      origin:DedaSessionTransitionOrigin.activeSection,isCurrent:()=>true),
      throwsA(isA<DedaSessionTransitionDenied>()));
    expect(h.io.currentUser,same(admin));
    expect(h.io.events,isEmpty);
    h.gate.dispose();
  });
}
