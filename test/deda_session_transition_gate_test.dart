import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_session_transition_gate.dart';

Future<T> _run<T>(DedaSessionTransitionGate gate, {
  Object key = 'owner-intent',
  DedaSessionTransitionKind kind = DedaSessionTransitionKind.ownerLogin,
  DedaSessionTransitionOrigin origin = DedaSessionTransitionOrigin.userAction,
  DedaSessionAuthKind auth = DedaSessionAuthKind.anonymous,
  bool Function()? current,
  required Future<T> Function(DedaSessionTransitionPermit) action,
}) => gate.run<T>(key: key, kind: kind, origin: origin,
  currentAuthKind: () => auth, isCurrent: current ?? () => true, action: action);

void main() {
  test('uninitialized Firebase never counts as readiness for any purpose or session shape', () {
    for (final auth in DedaSessionAuthKind.values) {
      for (final purpose in DedaSessionPurpose.values) {
        expect(DedaSessionReadinessPolicy.inspect(firebaseReady: false,
          auth: auth, purpose: purpose), DedaSessionReadiness.firebaseNotReady);
      }
    }
  });

  test('SDK user is never owner or admin permission proof', () {
    for (final auth in [DedaSessionAuthKind.anonymous, DedaSessionAuthKind.authenticated]) {
      expect(DedaSessionReadinessPolicy.inspect(firebaseReady: true,
        auth: auth, purpose: DedaSessionPurpose.ownerData), DedaSessionReadiness.needOwnerProof);
    }
    expect(DedaSessionReadinessPolicy.inspect(firebaseReady: true,
      auth: DedaSessionAuthKind.authenticated, purpose: DedaSessionPurpose.adminData),
      DedaSessionReadiness.needAdminProof);
    expect(DedaSessionReadinessPolicy.inspect(firebaseReady: true,
      auth: DedaSessionAuthKind.anonymous, purpose: DedaSessionPurpose.adminData),
      DedaSessionReadiness.needAdminLogin);
  });

  test('public session presence does not imply owner readiness', () {
    expect(DedaSessionReadinessPolicy.inspect(firebaseReady: true,
      auth: DedaSessionAuthKind.authenticated, purpose: DedaSessionPurpose.publicData),
      DedaSessionReadiness.sessionPresent);
    expect(DedaSessionReadinessPolicy.inspect(firebaseReady: true,
      auth: DedaSessionAuthKind.none, purpose: DedaSessionPurpose.ownerData),
      DedaSessionReadiness.needAnonymousSession);
  });

  test('background cannot start any mutation even with a protected SDK session', () async {
    final gate = DedaSessionTransitionGate();
    var calls = 0;
    for (final kind in DedaSessionTransitionKind.values) {
      await expectLater(_run<int>(gate, kind: kind,
        origin: DedaSessionTransitionOrigin.background,
        auth: DedaSessionAuthKind.authenticated,
        action: (_) async { calls++; return 1; }),
        throwsA(isA<DedaSessionTransitionDenied>()));
    }
    expect(calls, 0);
    expect(gate.diagnostics['inFlight'], 0);
    gate.dispose();
  });

  test('active-section owner restore never signs out a protected session', () async {
    final gate = DedaSessionTransitionGate();
    var signOutCalls = 0;
    await expectLater(_run<int>(gate,
      kind: DedaSessionTransitionKind.ownerRestore,
      origin: DedaSessionTransitionOrigin.activeSection,
      auth: DedaSessionAuthKind.authenticated,
      action: (_) async { signOutCalls++; return 1; }),
      throwsA(isA<DedaSessionTransitionDenied>()));
    expect(signOutCalls, 0);
    gate.dispose();
  });

  test('anonymous preparation reuses observation instead of replacing an existing session', () async {
    final gate = DedaSessionTransitionGate();
    var calls = 0;
    for (final auth in [DedaSessionAuthKind.anonymous, DedaSessionAuthKind.authenticated]) {
      await expectLater(_run<int>(gate,
        kind: DedaSessionTransitionKind.anonymousPreparation,
        origin: DedaSessionTransitionOrigin.activeSection, auth: auth,
        action: (_) async { calls++; return 1; }),
        throwsA(isA<DedaSessionTransitionDenied>()));
    }
    expect(calls, 0);
    expect(await _run<int>(gate,
      kind: DedaSessionTransitionKind.anonymousPreparation,
      origin: DedaSessionTransitionOrigin.activeSection,
      auth: DedaSessionAuthKind.none,
      action: (_) async { calls++; return 7; }), 7);
    expect(calls, 1);
    gate.dispose();
  });

  test('active owner restore is admitted only for an anonymous session', () async {
    final gate = DedaSessionTransitionGate();
    expect(await _run<int>(gate, kind: DedaSessionTransitionKind.ownerRestore,
      origin: DedaSessionTransitionOrigin.activeSection,
      action: (permit) async { permit.checkCurrent(); return 1; }), 1);
    await expectLater(_run<int>(gate, kind: DedaSessionTransitionKind.adminLogin,
      origin: DedaSessionTransitionOrigin.activeSection,
      action: (_) async => 2), throwsA(isA<DedaSessionTransitionDenied>()));
    gate.dispose();
  });

  test('identical concurrent explicit requests share one action, not a cached later result', () async {
    final gate = DedaSessionTransitionGate();
    final sdk = Completer<int>();
    var calls = 0;
    Future<int> action(DedaSessionTransitionPermit _) { calls++; return sdk.future; }
    final first = _run<int>(gate, action: action);
    final second = _run<int>(gate, action: action);
    expect(identical(first, second), isTrue);
    expect(calls, 1);
    sdk.complete(4);
    expect(await first, 4);
    expect(await second, 4);
    expect(await _run<int>(gate, action: (_) async { calls++; return 9; }), 9);
    expect(calls, 2);
    expect(gate.diagnostics['joined'], 1);
    gate.dispose();
  });

  test('different admin intent fails busy and is never queued behind an owner', () async {
    final gate = DedaSessionTransitionGate();
    final sdk = Completer<int>();
    var adminCalls = 0;
    final owner = _run<int>(gate, action: (_) => sdk.future);
    await expectLater(_run<int>(gate, key: 'admin', kind: DedaSessionTransitionKind.adminLogin,
      action: (_) async { adminCalls++; return 2; }),
      throwsA(isA<DedaSessionTransitionBusy>()));
    sdk.complete(1);
    expect(await owner, 1);
    await Future<void>.delayed(Duration.zero);
    expect(adminCalls, 0);
    expect(await _run<int>(gate, key: 'admin', kind: DedaSessionTransitionKind.adminLogin,
      action: (_) async { adminCalls++; return 2; }), 2);
    expect(adminCalls, 1);
    gate.dispose();
  });

  test('same key cannot join a different transition, origin or result type', () async {
    final gate = DedaSessionTransitionGate();
    final sdk = Completer<int>();
    final first = _run<int>(gate, action: (_) => sdk.future);
    await expectLater(_run<int>(gate, kind: DedaSessionTransitionKind.logout,
      action: (_) async => 2), throwsA(isA<DedaSessionTransitionBusy>()));
    await expectLater(_run<int>(gate, origin: DedaSessionTransitionOrigin.activeSection,
      action: (_) async => 2), throwsA(isA<DedaSessionTransitionBusy>()));
    await expectLater(_run<String>(gate, action: (_) async => 'wrong-type'),
      throwsA(isA<DedaSessionTransitionBusy>()));
    sdk.complete(1);
    expect(await first, 1);
    gate.dispose();
  });

  test('timeout retains the real SDK barrier and repeated intent cannot start again', () async {
    final gate = DedaSessionTransitionGate(timeout: const Duration(milliseconds: 50));
    final sdk = Completer<int>();
    var calls = 0;
    Future<int> action(DedaSessionTransitionPermit _) { calls++; return sdk.future; }
    final first = _run<int>(gate, action: action);
    await expectLater(first, throwsA(isA<TimeoutException>()));
    expect(gate.diagnostics['inFlight'], 1);
    final repeated = _run<int>(gate, action: action);
    expect(identical(first, repeated), isTrue);
    await expectLater(repeated, throwsA(isA<TimeoutException>()));
    await expectLater(_run<int>(gate, key: 'admin', action: action),
      throwsA(isA<DedaSessionTransitionBusy>()));
    expect(calls, 1);
    sdk.complete(99);
    await Future<void>.delayed(Duration.zero);
    expect(gate.diagnostics['inFlight'], 0);
    expect(gate.diagnostics['succeeded'], 0);
    expect(gate.diagnostics['lateSettled'], 1);
    expect(await _run<int>(gate, action: (_) async => 5), 5);
    gate.dispose();
  });

  test('late SDK side effect remains possible while permit prevents subsequent profile writes', () async {
    final gate = DedaSessionTransitionGate(timeout: const Duration(milliseconds: 50));
    final sdk = Completer<void>();
    var sdkCalls = 0, profileWrites = 0;
    var auth = DedaSessionAuthKind.none;
    final result = _run<String>(gate, action: (permit) async {
      sdkCalls++;
      await sdk.future;
      auth = DedaSessionAuthKind.anonymous; // SDK may complete after UI timeout.
      permit.checkCurrent();
      profileWrites++;
      return 'owner';
    });
    await expectLater(result, throwsA(isA<TimeoutException>()));
    sdk.complete();
    await Future<void>.delayed(Duration.zero);
    expect(auth, DedaSessionAuthKind.anonymous);
    expect(sdkCalls, 1);
    expect(profileWrites, 0);
    expect(gate.diagnostics['inFlight'], 0);
    gate.dispose();
  });

  test('late SDK errors are observed without automatic retry', () async {
    final gate = DedaSessionTransitionGate(timeout: const Duration(milliseconds: 50));
    final sdk = Completer<int>();
    var calls = 0;
    final result = _run<int>(gate, action: (_) { calls++; return sdk.future; });
    await expectLater(result, throwsA(isA<TimeoutException>()));
    sdk.completeError(StateError('late-failure'));
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    expect(gate.diagnostics['lateSettled'], 1);
    expect(gate.diagnostics['inFlight'], 0);
    gate.dispose();
  });

  test('A B A intent invalidation never revives first A and holds lane until actual settlement', () async {
    final gate = DedaSessionTransitionGate();
    final sdk = Completer<int>();
    var started = 0;
    final old = expectLater(_run<int>(gate, key: 'A',
      action: (_) { started++; return sdk.future; }),
      throwsA(isA<DedaStaleSessionTransition>()));
    gate.invalidate();
    gate.invalidate();
    await expectLater(_run<int>(gate, key: 'A', action: (_) async { started++; return 2; }),
      throwsA(isA<DedaSessionTransitionBusy>()));
    sdk.complete(1);
    await old;
    await Future<void>.delayed(Duration.zero);
    expect(await _run<int>(gate, key: 'A', action: (_) async { started++; return 3; }), 3);
    expect(started, 2);
    expect(gate.diagnostics['succeeded'], 1);
    gate.dispose();
  });

  test('changed live intent cannot publish success even without explicit invalidation', () async {
    final gate = DedaSessionTransitionGate();
    final sdk = Completer<int>();
    var current = true;
    final result = _run<int>(gate, current: () => current, action: (_) => sdk.future);
    final outcome = expectLater(result, throwsA(isA<DedaStaleSessionTransition>()));
    current = false;
    sdk.complete(1);
    await outcome;
    expect(gate.diagnostics['succeeded'], 0);
    gate.dispose();
  });

  test('expected SDK state change during admitted login does not invalidate the user intent', () async {
    final gate = DedaSessionTransitionGate();
    var auth = DedaSessionAuthKind.none;
    final result = await gate.run<String>(key: 'explicit-admin',
      kind: DedaSessionTransitionKind.adminLogin,
      origin: DedaSessionTransitionOrigin.userAction,
      currentAuthKind: () => auth, isCurrent: () => true,
      action: (permit) async {
        auth = DedaSessionAuthKind.authenticated;
        permit.checkCurrent(); // Expected auth event is not an intent change.
        return 'server-proof-still-required';
      });
    expect(result, 'server-proof-still-required');
    expect(auth, DedaSessionAuthKind.authenticated);
    gate.dispose();
  });

  test('synchronous action failure preserves the error and frees lane without retry', () async {
    final gate = DedaSessionTransitionGate();
    final error = StateError('secret-error-not-for-diagnostics');
    var calls = 0;
    await expectLater(_run<int>(gate, action: (_) { calls++; throw error; }),
      throwsA(same(error)));
    expect(calls, 1);
    expect(await _run<int>(gate, action: (_) async => 2), 2);
    expect(gate.diagnostics.toString(), isNot(contains('secret-error')));
    gate.dispose();
  });

  test('nested helpers cannot await their own transition or silently reenter another one', () async {
    final gate = DedaSessionTransitionGate();
    var nestedCalls = 0;
    await expectLater(_run<int>(gate, action: (_) =>
      _run<int>(gate, action: (_) async { nestedCalls++; return 2; })),
      throwsA(isA<DedaSessionTransitionReentrant>()));
    expect(nestedCalls, 0);
    expect(gate.diagnostics['inFlight'], 0);
    expect(await _run<int>(gate, action: (_) async => 3), 3);
    gate.dispose();
  });

  test('dispose ends caller wait but holds and observes the outstanding SDK request', () async {
    final gate = DedaSessionTransitionGate();
    final sdk = Completer<int>();
    final old = expectLater(_run<int>(gate, action: (_) => sdk.future),
      throwsA(isA<DedaStaleSessionTransition>()));
    gate.dispose();
    gate.dispose();
    expect(gate.diagnostics['inFlight'], 1);
    await expectLater(_run<int>(gate, action: (_) async => 2),
      throwsA(isA<DedaSessionGateClosed>()));
    sdk.complete(1);
    await old;
    await Future<void>.delayed(Duration.zero);
    expect(gate.diagnostics['inFlight'], 0);
    expect(gate.diagnostics['succeeded'], 0);
  });

  test('stale admission and invalid policies cannot execute an action', () async {
    expect(() => DedaSessionTransitionGate(timeout: Duration.zero), throwsArgumentError);
    final gate = DedaSessionTransitionGate();
    var calls = 0;
    await expectLater(_run<int>(gate, current: () => false,
      action: (_) async { calls++; return 1; }),
      throwsA(isA<DedaStaleSessionTransition>()));
    expect(calls, 0);
    gate.dispose();
  });

  test('diagnostics are fixed aggregate counts and cannot expose private request keys', () async {
    final gate = DedaSessionTransitionGate();
    await _run<int>(gate, key: 'private-phone-account-key', action: (_) async => 1);
    expect(gate.diagnostics.keys.toSet(), {
      'started','joined','busy','denied','succeeded','failed','timedOut',
      'invalidated','lateSettled','inFlight',
    });
    expect(gate.diagnostics.toString(), isNot(contains('private-phone')));
    expect(gate.diagnostics.values.every((count) => count >= 0), isTrue);
    expect(() => gate.diagnostics['started'] = 0, throwsUnsupportedError);
    gate.dispose();
  });
}
