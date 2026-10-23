import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_session_transition_gate.dart';
import 'package:d_iraq_ludo/deda_session_flow_prototype.dart';

const _account = 'fixture-owner-A';
const _pin = '123456'; // Synthetic test input, never a real credential.
const _explicit = DedaSessionTransitionOrigin.userAction;

class _Port implements DedaSessionFlowPort {
  @override
  bool firebaseReady = true;
  @override
  DedaFlowSdkUser? currentUser;
  int revision = 0;
  int anonymousCalls = 0;
  final events = <String>[];
  final holds = <String, Completer<void>>{};
  final failures = <String, Object>{};
  final after = <String, void Function()>{};
  bool trusted = true;
  bool ownerVerified = true;
  bool adminActive = true;
  String? proofUid, proofAccount, profileUid, profileAccount, profileName, adminProofUid;
  String? sessionAccount;

  DedaFlowSdkUser setUser(String uid, DedaSessionAuthKind kind) {
    final user = DedaFlowSdkUser(uid, kind, ++revision);
    currentUser = user;
    return user;
  }

  Future<void> visit(String label, DedaSessionTransitionPermit permit, {bool dispatchedSdk = false}) async {
    permit.checkCurrent();
    events.add(label);
    final wait = holds[label];
    if (wait != null) await wait.future;
    after[label]?.call();
    final failure = failures[label];
    if (failure != null) throw failure;
    if (!dispatchedSdk) permit.checkCurrent();
  }

  void checkUser(DedaSessionTransitionPermit permit, DedaFlowSdkUser user) {
    permit.checkCurrent();
    if (currentUser?.uid != user.uid || currentUser?.kind != user.kind ||
        currentUser?.revision != user.revision) {
      throw const DedaStaleSessionTransition();
    }
  }

  @override
  Future<bool> signOutIfCurrent(DedaSessionTransitionPermit permit, DedaFlowSdkUser expected) async {
    if (currentUser?.uid != expected.uid || currentUser?.revision != expected.revision) return false;
    await visit('sdk.signOut', permit, dispatchedSdk: true);
    currentUser = null;
    revision++;
    return true;
  }
  @override
  Future<DedaFlowSdkUser> signInAnonymous(DedaSessionTransitionPermit permit) async {
    anonymousCalls++;
    await visit('sdk.anonymous', permit, dispatchedSdk: true);
    // Already dispatched SDK effects may happen even after the UI times out.
    return setUser('fixture-anonymous-$anonymousCalls', DedaSessionAuthKind.anonymous);
  }
  @override
  Future<void> provePin(DedaSessionTransitionPermit permit, DedaFlowSdkUser user, String accountKey, String pin) async {
    await visit('pin', permit);
    if (pin != _pin) throw StateError('fixture-pin-denied');
  }
  @override
  Future<void> writeOwnerSession(DedaSessionTransitionPermit permit, DedaFlowSdkUser user,
      String accountKey, {required bool trustedRestore}) async {
    await visit(trustedRestore ? 'session.restore' : 'session.pin', permit);
    if (trustedRestore && !trusted) throw StateError('fixture-install-denied');
    sessionAccount = accountKey;
  }
  @override
  Future<DedaOwnerSessionProof> readOwnerProof(DedaSessionTransitionPermit permit,
      DedaFlowSdkUser user, String accountKey) async {
    await visit('owner.proof', permit);
    return DedaOwnerSessionProof(uid: proofUid ?? user.uid,
      accountKey: proofAccount ?? sessionAccount ?? '',
      ownerVerified: ownerVerified, trustedInstallation: trusted);
  }
  @override
  Future<DedaOwnerFlowProfile> readOwnerProfile(DedaSessionTransitionPermit permit,
      DedaFlowSdkUser user, String accountKey) async {
    await visit('owner.profile', permit);
    return DedaOwnerFlowProfile(uid: profileUid ?? user.uid,
      accountKey: profileAccount ?? accountKey, name: profileName ?? 'Fixture Owner',
      phone: 'fixture-phone', accountType: 'user');
  }
  @override
  Future<void> trustOwnerDevice(DedaSessionTransitionPermit permit,
      DedaFlowSdkUser user, String accountKey) async {
    await visit('trust.prepare', permit); // e.g. waiting for local installId.
    checkUser(permit, user);
    await visit('trust.write', permit);
  }
  @override
  Future<void> writeOwnerProjection(DedaSessionTransitionPermit permit,
      DedaFlowSdkUser user, DedaOwnerFlowProfile profile) => visit('owner.projection', permit);
  @override
  Future<void> rememberKnownOwner(DedaSessionTransitionPermit permit, DedaFlowSdkUser user, String accountKey) async {
    await visit('remember.prepare', permit);
    checkUser(permit, user);
    events.add('remember.write');
  }
  @override
  Future<DedaFlowSdkUser> signInAdmin(DedaSessionTransitionPermit permit, String email, String password) async {
    await visit('sdk.admin', permit, dispatchedSdk: true);
    return setUser('fixture-admin', DedaSessionAuthKind.authenticated);
  }
  @override
  Future<DedaAdminSessionProof> readAdminProof(DedaSessionTransitionPermit permit, DedaFlowSdkUser user) async {
    await visit('admin.proof', permit);
    return DedaAdminSessionProof(uid: adminProofUid ?? user.uid,
      active: adminActive, role: 'general_manager');
  }
  @override
  Future<void> refreshAdminProfile(DedaSessionTransitionPermit permit,
      DedaFlowSdkUser user, DedaAdminSessionProof proof) => visit('admin.profile', permit);
  @override
  Future<void> registerAdminNotifications(DedaSessionTransitionPermit permit,
      DedaFlowSdkUser user) => visit('notifications', permit);
  @override
  Future<void> writeAdminAudit(DedaSessionTransitionPermit permit,
      DedaFlowSdkUser user, DedaAdminSessionProof proof) => visit('admin.audit', permit);
}

class _Harness {
  _Harness({bool shortWait = false}) {
    gate = DedaSessionTransitionGate(timeout: Duration(milliseconds: shortWait ? 50 : 12000));
    flow = DedaSessionFlowPrototype(port: port, gate: gate);
  }
  final port = _Port();
  late final DedaSessionTransitionGate gate;
  late final DedaSessionFlowPrototype flow;
  bool current = true;
  Future<DedaOwnerFlowResult> login({String pin = _pin,
    DedaSessionTransitionOrigin origin = _explicit}) => flow.ownerLogin(
      accountKey: _account, pin: pin, origin: origin, isCurrent: () => current);
  Future<DedaOwnerFlowResult> restore({DedaSessionTransitionOrigin origin = _explicit}) =>
    flow.restoreOwner(accountKey: _account, origin: origin, isCurrent: () => current);
  Future<DedaAdminFlowResult> admin({DedaSessionTransitionOrigin origin = _explicit}) =>
    flow.adminLogin(email: 'fixture@example.invalid', password: 'fixture-only-password',
      origin: origin, isCurrent: () => current);
  Completer<void> hold(String label) {
    final value = Completer<void>();
    port.holds[label] = value;
    return value;
  }
  Future<void> flush() => Future<void>.delayed(Duration.zero);
}

Future<void> _reached(_Harness h, String label) async {
  for (var i = 0; i < 20 && !h.port.events.contains(label); i++) { await h.flush(); }
  expect(h.port.events, contains(label));
}

void main() {
  test('owner login runs the complete guarded sequence without nested gate entry', () async {
    final h = _Harness();
    h.port.trusted = false; // Valid PIN can trust a new device later in the flow.
    final result = await h.login();
    expect(result.profile?.name, 'Fixture Owner');
    expect(result.proof.accountKey, _account);
    expect(h.port.events, ['sdk.anonymous','pin','session.pin','owner.proof','owner.profile',
      'trust.prepare','trust.write','owner.projection','remember.prepare','remember.write']);
    expect(h.gate.diagnostics['started'], 1);
    h.gate.dispose();
  });

  test('trusted restore reuses anonymous SDK and never proves PIN or rewrites a profile', () async {
    final h = _Harness();
    h.port.setUser('existing-owner', DedaSessionAuthKind.anonymous);
    final result = await h.restore(origin: DedaSessionTransitionOrigin.activeSection);
    expect(result.profile, isNull);
    expect(h.port.events, ['session.restore','owner.proof']);
    expect(h.port.anonymousCalls, 0);
    h.gate.dispose();
  });

  test('explicit trusted restore from no SDK session creates one and verifies server proof', () async {
    final h = _Harness();
    final result = await h.restore();
    expect(result.proof.trustedInstallation, isTrue);
    expect(h.port.events, ['sdk.anonymous','session.restore','owner.proof']);
    h.gate.dispose();
  });

  test('active-section restore cannot end a protected administration session', () async {
    final h = _Harness();
    final admin = h.port.setUser('protected', DedaSessionAuthKind.authenticated);
    await expectLater(h.restore(origin: DedaSessionTransitionOrigin.activeSection),
      throwsA(isA<DedaSessionTransitionDenied>()));
    expect(h.port.currentUser, same(admin));
    expect(h.port.events, isEmpty);
    h.gate.dispose();
  });

  test('background never starts owner login, restore or admin login', () async {
    final h = _Harness();
    await expectLater(h.login(origin: DedaSessionTransitionOrigin.background),
      throwsA(isA<DedaSessionTransitionDenied>()));
    await expectLater(h.restore(origin: DedaSessionTransitionOrigin.background),
      throwsA(isA<DedaSessionTransitionDenied>()));
    await expectLater(h.admin(origin: DedaSessionTransitionOrigin.background),
      throwsA(isA<DedaSessionTransitionDenied>()));
    expect(h.port.events, isEmpty);
    h.gate.dispose();
  });

  test('invalid input and missing Firebase never reach the fake SDK', () async {
    final h = _Harness();
    await expectLater(h.login(pin: 'bad'), throwsArgumentError);
    h.port.firebaseReady = false;
    await expectLater(h.login(), throwsStateError);
    expect(h.port.events, isEmpty);
    h.gate.dispose();
  });

  test('wrong PIN stops before session and profile writes without retry or logout', () async {
    final h = _Harness();
    await expectLater(h.login(pin: '999999'), throwsStateError);
    expect(h.port.events, ['sdk.anonymous','pin']);
    expect(h.port.anonymousCalls, 1);
    expect(h.port.currentUser?.kind, DedaSessionAuthKind.anonymous);
    h.gate.dispose();
  });

  test('untrusted install cannot restore even if the account key is locally known', () async {
    final h = _Harness();
    h.port.trusted = false;
    await expectLater(h.restore(), throwsStateError);
    expect(h.port.events, ['sdk.anonymous','session.restore']);
    h.gate.dispose();
  });

  for (final field in ['uid','account','verified']) {
    test('owner server proof rejects mismatched $field before profile access', () async {
      final h = _Harness();
      if (field == 'uid') h.port.proofUid = 'different';
      if (field == 'account') h.port.proofAccount = 'different';
      if (field == 'verified') h.port.ownerVerified = false;
      await expectLater(h.login(), throwsA(isA<DedaSessionProofRejected>()));
      expect(h.port.events, isNot(contains('owner.profile')));
      expect(h.port.events, isNot(contains('sdk.signOut')));
      h.gate.dispose();
    });
  }

  for (final field in ['uid','account','name']) {
    test('owner profile rejects mismatched $field before trust and projection writes', () async {
      final h = _Harness();
      if (field == 'uid') h.port.profileUid = 'different';
      if (field == 'account') h.port.profileAccount = 'different';
      if (field == 'name') h.port.profileName = ' ';
      await expectLater(h.login(), throwsA(isA<DedaSessionProofRejected>()));
      expect(h.port.events, isNot(contains('trust.prepare')));
      expect(h.port.events, isNot(contains('owner.projection')));
      h.gate.dispose();
    });
  }

  test('late SDK login may complete but cannot prove PIN or publish after UI timeout', () async {
    final h = _Harness(shortWait: true);
    final hold = h.hold('sdk.anonymous');
    await expectLater(h.login(), throwsA(isA<TimeoutException>()));
    await expectLater(h.admin(), throwsA(isA<DedaSessionTransitionBusy>()));
    expect(h.gate.diagnostics['inFlight'], 1);
    hold.complete();
    await h.flush();
    expect(h.port.currentUser?.kind, DedaSessionAuthKind.anonymous);
    expect(h.port.events, ['sdk.anonymous']);
    expect(h.gate.diagnostics['inFlight'], 0);
    h.gate.dispose();
  });

  test('late explicit sign-out cannot continue to a new anonymous login', () async {
    final h = _Harness(shortWait: true);
    h.port.setUser('admin-before-owner-login', DedaSessionAuthKind.authenticated);
    final hold = h.hold('sdk.signOut');
    await expectLater(h.login(), throwsA(isA<TimeoutException>()));
    hold.complete();
    await h.flush();
    expect(h.port.currentUser, isNull);
    expect(h.port.events, ['sdk.signOut']);
    expect(h.port.anonymousCalls, 0);
    h.gate.dispose();
  });

  test('late local install preparation cannot dispatch the subsequent trust write', () async {
    final h = _Harness(shortWait: true);
    final hold = h.hold('trust.prepare');
    await expectLater(h.login(), throwsA(isA<TimeoutException>()));
    expect(h.port.events.last, 'trust.prepare');
    hold.complete();
    await h.flush();
    expect(h.port.events, isNot(contains('trust.write')));
    expect(h.port.events, isNot(contains('owner.projection')));
    h.gate.dispose();
  });

  for (final preparation in ['trust.prepare', 'remember.prepare']) {
    test('principal change during $preparation prevents the next nested write', () async {
      final h = _Harness();
      final hold = h.hold(preparation);
      final result = h.login();
      final outcome = expectLater(result, throwsA(isA<DedaStaleSessionTransition>()));
      await _reached(h, preparation);
      h.port.setUser('newer-during-local-preparation', DedaSessionAuthKind.authenticated);
      hold.complete();
      await outcome;
      final forbidden = preparation == 'trust.prepare' ? 'trust.write' : 'remember.write';
      expect(h.port.events, isNot(contains(forbidden)));
      h.gate.dispose();
    });
  }

  test('already dispatched projection is not retried and cannot trigger late local remember', () async {
    final h = _Harness(shortWait: true);
    final hold = h.hold('owner.projection');
    await expectLater(h.login(), throwsA(isA<TimeoutException>()));
    expect(h.port.events.where((e) => e == 'owner.projection'), hasLength(1));
    hold.complete();
    await h.flush();
    expect(h.port.events, isNot(contains('remember.prepare')));
    expect(h.gate.diagnostics['succeeded'], 0);
    h.gate.dispose();
  });

  test('cancelled owner intent cannot continue after a delayed proof', () async {
    final h = _Harness();
    final hold = h.hold('owner.proof');
    final result = h.login();
    final outcome = expectLater(result, throwsA(isA<DedaStaleSessionTransition>()));
    await _reached(h, 'owner.proof');
    h.current = false;
    h.gate.invalidate();
    await outcome;
    hold.complete();
    await h.flush();
    expect(h.port.events, isNot(contains('owner.profile')));
    expect(h.port.events, isNot(contains('sdk.signOut')));
    h.gate.dispose();
  });

  test('SDK A B A principal revision rejects stale owner profile even with the same UID', () async {
    final h = _Harness();
    final original = h.port.setUser('same-A', DedaSessionAuthKind.anonymous);
    final hold = h.hold('owner.profile');
    final result = h.login();
    final outcome = expectLater(result, throwsA(isA<DedaStaleSessionTransition>()));
    await _reached(h, 'owner.profile');
    h.port.setUser('B', DedaSessionAuthKind.anonymous);
    h.port.setUser(original.uid, original.kind);
    hold.complete();
    await outcome;
    expect(h.port.events, isNot(contains('trust.prepare')));
    h.gate.dispose();
  });

  test('principal change after PIN proof cannot open a session for the previous owner', () async {
    final h = _Harness();
    h.port.after['pin'] = () { h.port.setUser('unexpected', DedaSessionAuthKind.authenticated); };
    await expectLater(h.login(), throwsA(isA<DedaStaleSessionTransition>()));
    expect(h.port.events, isNot(contains('session.pin')));
    expect(h.port.events, isNot(contains('sdk.signOut')));
    h.gate.dispose();
  });

  test('admin cannot interleave with complete owner flow and runs only on a new explicit call', () async {
    final h = _Harness();
    final hold = h.hold('pin');
    final owner = h.login();
    await _reached(h, 'pin');
    await expectLater(h.admin(), throwsA(isA<DedaSessionTransitionBusy>()));
    expect(h.port.events, isNot(contains('sdk.admin')));
    hold.complete();
    await owner;
    final admin = await h.admin();
    expect(admin.proof.active, isTrue);
    expect(h.port.events.indexOf('sdk.admin'), greaterThan(h.port.events.indexOf('remember.write')));
    h.gate.dispose();
  });

  test('a repeated tap with different PIN cannot join the prior credential attempt', () async {
    final h = _Harness();
    final hold = h.hold('pin');
    final first = h.login();
    await _reached(h, 'pin');
    await expectLater(h.login(pin: '999999'), throwsA(isA<DedaSessionTransitionBusy>()));
    hold.complete();
    await first;
    expect(h.port.events.where((e) => e == 'pin'), hasLength(1));
    h.gate.dispose();
  });

  test('valid admin performs server proof before updates, notifications and audit', () async {
    final h = _Harness();
    final result = await h.admin();
    expect(result.proof.uid, result.user.uid);
    expect(h.port.events, ['sdk.admin','admin.proof','admin.profile','notifications','admin.audit']);
    h.gate.dispose();
  });

  test('inactive admin rejection signs out only its still-current SDK session', () async {
    final h = _Harness();
    h.port.adminActive = false;
    await expectLater(h.admin(), throwsA(isA<DedaSessionProofRejected>()));
    expect(h.port.events, ['sdk.admin','admin.proof','sdk.signOut']);
    expect(h.port.currentUser, isNull);
    h.gate.dispose();
  });

  for (final sameUid in [false, true]) {
    test('late rejected admin proof cannot sign out a newer ${sameUid ? 'same-UID revision' : 'principal'}', () async {
      final h = _Harness();
      h.port.adminActive = false;
      final hold = h.hold('admin.proof');
      final result = h.admin();
      final outcome = expectLater(result, throwsA(isA<DedaStaleSessionTransition>()));
      await _reached(h, 'admin.proof');
      final newer = h.port.setUser(sameUid ? 'fixture-admin' : 'newer-admin', DedaSessionAuthKind.authenticated);
      hold.complete();
      await outcome;
      expect(h.port.currentUser, same(newer));
      expect(h.port.events, isNot(contains('sdk.signOut')));
      h.gate.dispose();
    });
  }

  test('late inactive admin proof after timeout never dispatches a cleanup logout', () async {
    final h = _Harness(shortWait: true);
    h.port.adminActive = false;
    final hold = h.hold('admin.proof');
    await expectLater(h.admin(), throwsA(isA<TimeoutException>()));
    hold.complete();
    await h.flush();
    expect(h.port.events, ['sdk.admin','admin.proof']);
    expect(h.port.currentUser?.kind, DedaSessionAuthKind.authenticated);
    expect(h.gate.diagnostics['succeeded'], 0);
    h.gate.dispose();
  });

  test('notification failure is secondary and does not turn confirmed admin login into failure', () async {
    final h = _Harness();
    h.port.failures['notifications'] = StateError('fixture-fcm');
    final result = await h.admin();
    expect(result.proof.active, isTrue);
    expect(h.port.events.last, 'admin.audit');
    expect(h.port.events, isNot(contains('sdk.signOut')));
    h.gate.dispose();
  });

  test('audit failure preserves original error without replaying login or logging out a valid admin', () async {
    final h = _Harness();
    final error = StateError('fixture-audit');
    h.port.failures['admin.audit'] = error;
    await expectLater(h.admin(), throwsA(same(error)));
    expect(h.port.events.where((e) => e == 'sdk.admin'), hasLength(1));
    expect(h.port.events, isNot(contains('sdk.signOut')));
    h.gate.dispose();
  });

  test('timeout during notifications cannot publish or audit after a late failure', () async {
    final h = _Harness(shortWait: true);
    final hold = h.hold('notifications');
    h.port.failures['notifications'] = StateError('fixture-late-fcm');
    await expectLater(h.admin(), throwsA(isA<TimeoutException>()));
    await expectLater(h.login(), throwsA(isA<DedaSessionTransitionBusy>()));
    hold.complete();
    await h.flush();
    expect(h.port.events, isNot(contains('admin.audit')));
    expect(h.port.events, isNot(contains('sdk.signOut')));
    expect(h.port.currentUser?.kind, DedaSessionAuthKind.authenticated);
    expect(h.gate.diagnostics['succeeded'], 0);
    h.gate.dispose();
  });

  test('admin proof bound to another UID is never permission to update or sign out', () async {
    final h = _Harness();
    h.port.adminProofUid = 'different';
    await expectLater(h.admin(), throwsA(isA<DedaSessionProofRejected>()));
    expect(h.port.events, ['sdk.admin','admin.proof']);
    h.gate.dispose();
  });

  test('SDK replacement during admin update prevents notifications and later audit', () async {
    final h = _Harness();
    h.port.after['admin.profile'] = () { h.port.setUser('other', DedaSessionAuthKind.authenticated); };
    await expectLater(h.admin(), throwsA(isA<DedaStaleSessionTransition>()));
    expect(h.port.events, ['sdk.admin','admin.proof','admin.profile']);
    h.gate.dispose();
  });

  test('explicit owner login may leave an admin session once, while helper shares its permit', () async {
    final h = _Harness();
    h.port.setUser('admin', DedaSessionAuthKind.authenticated);
    await h.login();
    expect(h.port.events.take(3), ['sdk.signOut','sdk.anonymous','pin']);
    expect(h.port.events.where((e) => e == 'sdk.signOut'), hasLength(1));
    expect(h.gate.diagnostics['started'], 1);
    h.gate.dispose();
  });
}
