import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_admin_session_firebase_adapter.dart';
import 'package:d_iraq_ludo/deda_owner_session_firebase_port.dart';
import 'package:d_iraq_ludo/deda_session_flow_prototype.dart';
import 'package:d_iraq_ludo/deda_session_principal_tracker.dart';
import 'package:d_iraq_ludo/deda_session_transition_gate.dart';

const _explicit = DedaSessionTransitionOrigin.userAction;
class _Union { const _Union(this.values); final List<String> values; }
class _Io implements DedaAdminSessionIo {
  final tracker = DedaSessionPrincipalTracker();
  @override
  bool ready = true;
  @override
  DedaFlowSdkUser? currentUser;
  @override
  String? currentEmail = 'fixture@example.invalid';
  final events = <String>[];
  final holds = <String,Completer<void>>{};
  final failures = <String,Object>{};
  final after = <String,void Function()>{};
  final updates = <Map<String,dynamic>>[];
  final audits = <Map<String,dynamic>>[];
  Map<String,dynamic>? cachedProfile;
  Map<String,dynamic>? admin = {'active':true,'status':'active','role':'employee','displayName':'Fixture Admin'};
  bool proofCache = false, proofPending = false, auditCache = false, auditPending = false;
  bool nullCredential = false;
  String? token = 'fixture-token';
  String? receivedEmail, receivedPassword;
  int reads = 0;
  DedaFlowSdkUser? user(String? uid, [DedaSessionAuthKind kind = DedaSessionAuthKind.authenticated]) =>
    currentUser = tracker.observe(uid,kind);
  Future<void> visit(String label) async {
    events.add(label);
    if (holds[label] != null) await holds[label]!.future;
    after[label]?.call();
    if (failures[label] != null) throw failures[label]!;
  }
  @override
  void clearAdminProfileCache() { events.add('cache.clear'); cachedProfile = null; }
  @override
  void cacheAdminProfile(DedaFlowSdkUser user,Map<String,dynamic> profile) {
    expect(user.uid,currentUser!.uid);
    expect(user.revision,currentUser!.revision);
    events.add('cache.warm'); cachedProfile = Map.of(profile);
  }
  @override
  Future<DedaFlowSdkUser?> signIn(String email,String password) async {
    receivedEmail = email;
    receivedPassword = password;
    await visit('sdk.signIn');
    if (nullCredential) return null;
    return user('fixture-admin');
  }
  @override
  Future<void> signOut() async { await visit('sdk.signOut'); user(null); }
  @override
  Future<DedaOwnerServerDocument> readAdmin(String uid) async {
    expect(uid,'fixture-admin');
    final proof = ++reads == 1;
    await visit(proof ? 'read.proof' : 'read.audit');
    return DedaOwnerServerDocument(admin == null ? null : Map.of(admin!),
      fromCache:proof ? proofCache : auditCache, pendingWrites:proof ? proofPending : auditPending);
  }
  @override
  Future<void> mergeAdmin(String uid,Map<String,dynamic> fields) async {
    expect(uid,'fixture-admin');
    updates.add(Map.of(fields));
    await visit(fields.containsKey('fcmTokens') ? 'notification.write' : 'admin.update');
    admin?.addAll(fields);
  }
  @override
  Future<void> requestNotificationPermission() => visit('notification.permission');
  @override
  Future<String?> notificationToken() async { await visit('notification.token'); return token; }
  @override
  Future<void> addAudit(Map<String,dynamic> fields) async {
    audits.add(Map.of(fields));
    await visit('audit.write');
  }
  @override
  Object serverTimestamp() => 'fixture-server-timestamp';
  @override
  Object arrayUnion(List<String> values) => _Union(values);
}
class _Harness {
  _Harness({bool shortWait = false}) {
    gate = DedaSessionTransitionGate(timeout:Duration(milliseconds:shortWait ? 50 : 12000));
    adapter = DedaAdminSessionFirebaseAdapter(io:io,gate:gate);
  }
  final io = _Io();
  late final DedaSessionTransitionGate gate;
  late final DedaAdminSessionFirebaseAdapter adapter;
  bool current = true;
  Future<bool> login({String name = '',String password = 'fixture-password',
    DedaSessionTransitionOrigin origin = _explicit}) => adapter.signIn(
      email:' fixture@example.invalid ',password:password,displayName:name,
      origin:origin,isCurrent:()=>current);
  Completer<void> hold(String label) => io.holds[label] = Completer<void>();
}
Future<void> _reached(_Harness h,String label) async {
  for(var i=0;i<20 && !h.io.events.contains(label);i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(h.io.events,contains(label));
}
void main() {
  test('active admin follows full sequence and never writes entry authorization or permissions', () async {
    final h = _Harness();
    expect(await h.login(),isTrue);
    expect(h.io.events,['cache.clear','sdk.signIn','read.proof','admin.update',
      'notification.permission','notification.token','notification.write','read.audit','cache.warm','audit.write']);
    expect(h.io.receivedEmail,'fixture@example.invalid');
    expect(h.io.receivedPassword,'fixture-password');
    expect(h.io.updates[0].keys.toSet(),{'lastSeenAt','lastLoginAt'});
    expect(h.io.updates[1].keys.toSet(),{'fcmTokens','lastSeenAt'});
    expect((h.io.updates[1]['fcmTokens'] as _Union).values,['fixture-token']);
    expect(h.io.audits.single,{'action':'admin_signed_in','adminUid':'fixture-admin',
      'adminName':'Fixture Admin','adminRole':'employee','createdAt':'fixture-server-timestamp'});
    expect(h.gate.diagnostics['started'],1);
    h.gate.dispose();
  });
  test('optional display name preserves existing profile when empty or whitespace', () async {
    final h = _Harness();
    expect(await h.login(name:'   '),isTrue);
    expect(h.io.updates[0],isNot(contains('displayName')));
    expect(h.io.updates[0],isNot(contains('updatedAt')));
    expect(h.io.audits.single['adminName'],'Fixture Admin');
    h.gate.dispose();
  });
  test('nonempty display name is trimmed and later audit reads updated identity', () async {
    final h = _Harness();
    expect(await h.login(name:' New Fixture '),isTrue);
    expect(h.io.updates[0].keys.toSet(),{'lastSeenAt','lastLoginAt','displayName','updatedAt'});
    expect(h.io.updates[0]['displayName'],'New Fixture');
    expect(h.io.audits.single['adminName'],'New Fixture');
    expect(h.io.cachedProfile!['displayName'],'New Fixture');
    expect(h.io.cachedProfile!['uid'],'fixture-admin');
    expect(h.io.cachedProfile!['roleNormalized'],'employee');
    h.gate.dispose();
  });
  test('missing admin document returns false after ending only its current SDK session', () async {
    final h = _Harness();
    h.io.admin = null;
    expect(await h.login(),isFalse);
    expect(h.io.events,['cache.clear','sdk.signIn','read.proof','sdk.signOut']);
    expect(h.io.currentUser,isNull);
    expect(h.io.updates,isEmpty);
    h.gate.dispose();
  });
  test('null SDK credential returns false without proof or profile writes', () async {
    final h = _Harness();
    h.io.nullCredential = true;
    expect(await h.login(),isFalse);
    expect(h.io.events,['cache.clear','sdk.signIn']);
    h.gate.dispose();
  });
  for(final status in ['temporarily_stopped','disabled','active-flag-false','missing-status-disabled']) {
    test('admin rejection preserves existing status policy for $status', () async {
      final h = _Harness();
      if(status == 'active-flag-false') {
        h.io.admin!['active'] = false;
      } else if(status == 'missing-status-disabled') {
        h.io.admin!.remove('status'); h.io.admin!['active'] = false;
      } else {
        h.io.admin!['status'] = status;
      }
      await expectLater(h.login(),throwsA(isA<StateError>().having((e)=>e.message,'message',
        status == 'temporarily_stopped' ? 'admin-temporarily-stopped' : 'admin-disabled')));
      expect(h.io.events.last,'sdk.signOut');
      expect(h.io.updates,isEmpty);
      h.gate.dispose();
    });
  }
  test('legacy active record without status retains existing normalization', () async {
    final h = _Harness();
    h.io.admin!.remove('status');
    expect(await h.login(),isTrue);
    h.gate.dispose();
  });
  for(final role in ['assistant','staff','agent']) {
    test('audit role normalization retains existing legacy alias $role', () async {
      final h = _Harness();
      h.io.admin!['role'] = role;
      expect(await h.login(),isTrue);
      expect(h.io.audits.single['adminRole'],
        {'assistant':'deputy_manager','staff':'employee','agent':'province_agent'}[role]);
      expect(h.io.updates.every((u)=>!u.containsKey('role') && !u.containsKey('permissions')),isTrue);
      h.gate.dispose();
    });
  }
  for(final metadata in ['cache','pending']) {
    test('initial $metadata proof cannot confirm admin login or trigger writes or cleanup logout', () async {
      final h = _Harness();
      h.io.proofCache = metadata == 'cache'; h.io.proofPending = metadata == 'pending';
      await expectLater(h.login(),throwsA(isA<DedaSessionProofRejected>()));
      expect(h.io.updates,isEmpty);
      expect(h.io.events,isNot(contains('sdk.signOut')));
      h.gate.dispose();
    });
  }
  for(final step in ['sdk.signIn','read.proof','admin.update']) {
    test('primary failure at $step propagates unchanged without auth replay or logout', () async {
      final h = _Harness();
      final error = StateError('fixture-primary');
      h.io.failures[step] = error;
      await expectLater(h.login(),throwsA(same(error)));
      expect(h.io.events.where((e)=>e == 'sdk.signIn'),hasLength(1));
      expect(h.io.events,isNot(contains('sdk.signOut')));
      expect(h.io.audits,isEmpty);
      h.gate.dispose();
    });
  }
  for(final step in ['notification.permission','notification.token','notification.write']) {
    test('secondary failure at $step preserves confirmed login and best-effort audit', () async {
      final h = _Harness();
      h.io.failures[step] = StateError('fixture-fcm');
      expect(await h.login(),isTrue);
      expect(h.io.audits,hasLength(1));
      expect(h.io.events,isNot(contains('sdk.signOut')));
      h.gate.dispose();
    });
  }
  test('missing FCM token skips token write and preserves login and audit', () async {
    final h = _Harness();
    h.io.token = null;
    expect(await h.login(),isTrue);
    expect(h.io.updates,hasLength(1));
    expect(h.io.audits,hasLength(1));
    h.gate.dispose();
  });
  for(final step in ['read.audit','audit.write']) {
    test('secondary audit failure at $step preserves existing successful auth outcome', () async {
      final h = _Harness();
      h.io.failures[step] = StateError('fixture-audit');
      expect(await h.login(),isTrue);
      expect(h.io.events.where((e)=>e == 'sdk.signIn'),hasLength(1));
      expect(h.io.events,isNot(contains('sdk.signOut')));
      h.gate.dispose();
    });
  }
  for(final metadata in ['cache','pending']) {
    test('secondary audit $metadata read cannot supply actor identity', () async {
      final h = _Harness();
      h.io.auditCache = metadata == 'cache'; h.io.auditPending = metadata == 'pending';
      expect(await h.login(),isTrue);
      expect(h.io.audits,isEmpty);
      h.gate.dispose();
    });
  }
  test('revoked admin during notification skips audit and does not grant visibility via bool', () async {
    final h = _Harness();
    h.io.after['notification.token'] = () { h.io.admin!['active'] = false; };
    // Preserve the legacy bool contract; caller must separately recheck entry
    // and current admin authorization, which this adapter never grants.
    expect(await h.login(),isTrue);
    expect(h.io.audits,isEmpty);
    expect(h.io.updates.every((u)=>!u.containsKey('active')),isTrue);
    h.gate.dispose();
  });
  for(final step in ['sdk.signIn','read.proof','notification.permission','notification.token','read.audit','audit.write']) {
    test('UI timeout at $step retains SDK lane and prevents subsequent effects', () async {
      final h = _Harness(shortWait:true);
      final hold = h.hold(step);
      await expectLater(h.login(),throwsA(isA<TimeoutException>()));
      await expectLater(h.login(),throwsA(isA<DedaSessionTransitionBusy>()));
      final count = h.io.events.length;
      hold.complete();
      await Future<void>.delayed(Duration.zero);
      expect(h.io.events,hasLength(count));
      expect(h.gate.diagnostics['inFlight'],0);
      expect(h.gate.diagnostics['succeeded'],0);
      expect(h.io.events,isNot(contains('sdk.signOut')));
      h.gate.dispose();
    });
  }
  for(final step in ['read.proof','notification.permission','notification.token','read.audit']) {
    test('principal replacement during $step blocks all later effects', () async {
      final h = _Harness();
      final hold = h.hold(step);
      final outcome = expectLater(h.login(),throwsA(isA<DedaStaleSessionTransition>()));
      await _reached(h,step);
      final count = h.io.events.length;
      final replacement = h.io.user('newer-admin');
      hold.complete();
      await outcome;
      expect(h.io.events,hasLength(count));
      expect(h.io.currentUser,same(replacement));
      expect(h.io.events,isNot(contains('sdk.signOut')));
      h.gate.dispose();
    });
  }
  test('inactive proof from A B A cannot sign out a newer same-UID session', () async {
    final h = _Harness();
    h.io.admin!['active'] = false;
    final hold = h.hold('read.proof');
    final outcome = expectLater(h.login(),throwsA(isA<DedaStaleSessionTransition>()));
    await _reached(h,'read.proof');
    h.io.user('B'); final newer = h.io.user('fixture-admin');
    hold.complete(); await outcome;
    expect(h.io.currentUser,same(newer));
    expect(h.io.events,isNot(contains('sdk.signOut')));
    h.gate.dispose();
  });
  test('changed intent during delayed proof cannot publish or update after invalidation', () async {
    final h = _Harness();
    final hold = h.hold('read.proof');
    final outcome = expectLater(h.login(),throwsA(isA<DedaStaleSessionTransition>()));
    await _reached(h,'read.proof');
    h.current = false; h.gate.invalidate();
    await outcome; hold.complete();
    await Future<void>.delayed(Duration.zero);
    expect(h.io.updates,isEmpty);
    expect(h.io.events,isNot(contains('sdk.signOut')));
    h.gate.dispose();
  });
  test('different credentials cannot join or queue behind an active admin login', () async {
    final h = _Harness();
    final hold = h.hold('read.proof');
    final first = h.login();
    await _reached(h,'read.proof');
    await expectLater(h.login(password:'different-fixture'),throwsA(isA<DedaSessionTransitionBusy>()));
    hold.complete(); expect(await first,isTrue);
    expect(h.io.receivedPassword,'fixture-password');
    expect(h.io.events.where((e)=>e == 'sdk.signIn'),hasLength(1));
    h.gate.dispose();
  });
  test('owner and admin must share the same lane across their full transitions', () async {
    final h = _Harness();
    final hold = Completer<void>();
    final owner = h.gate.run<void>(key:Object(),kind:DedaSessionTransitionKind.ownerLogin,
      origin:_explicit,currentAuthKind:()=>DedaSessionAuthKind.none,isCurrent:()=>true,
      action:(permit)=>hold.future);
    await Future<void>.delayed(Duration.zero);
    await expectLater(h.login(),throwsA(isA<DedaSessionTransitionBusy>()));
    expect(h.io.events,isEmpty);
    hold.complete(); await owner;
    expect(await h.login(),isTrue);
    h.gate.dispose();
  });
  test('parent entry flow inherits one permit and retains the lane after backend login', () async {
    final h = _Harness();
    final entryCheck = Completer<void>();
    final reachedEntry = Completer<void>();
    final parent = h.gate.run<bool>(key:Object(),kind:DedaSessionTransitionKind.adminLogin,
      origin:_explicit,currentAuthKind:()=>DedaSessionAuthKind.none,isCurrent:()=>true,
      action:(permit) async {
        final allowed = await h.adapter.signInWithPermit(permit:permit,
          email:'fixture@example.invalid',password:'fixture-password');
        permit.checkCurrent();
        reachedEntry.complete();
        await entryCheck.future;
        permit.checkCurrent();
        return allowed;
      });
    await reachedEntry.future;
    await expectLater(h.login(),throwsA(isA<DedaSessionTransitionBusy>()));
    expect(h.gate.diagnostics['started'],1);
    entryCheck.complete();
    expect(await parent,isTrue);
    expect(h.io.events.where((e)=>e == 'sdk.signIn'),hasLength(1));
    h.gate.dispose();
  });
  test('background and missing Firebase never clear cache or call SDK', () async {
    final h = _Harness();
    await expectLater(h.login(origin:DedaSessionTransitionOrigin.background),throwsA(isA<DedaSessionTransitionDenied>()));
    h.io.ready = false;
    await expectLater(h.login(),throwsStateError);
    expect(h.io.events,isEmpty);
    h.gate.dispose();
  });
}
