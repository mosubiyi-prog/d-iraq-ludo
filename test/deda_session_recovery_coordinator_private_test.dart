import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_session_recovery_coordinator.dart';

const originalAccount = '9647712345678';
const anotherAccount = '9647712345679';

class FakeRescuePort implements DedaRescuePort {
  bool ready = true;
  DedaRescueSnapshot current = const DedaRescueSnapshot(
    uid: 'original-immutable-uid', epoch: 7, anonymous: false,
  );

  int reads = 0;
  int tokenRefreshes = 0;
  int guardedCalls = 0;
  Future<DedaRescueEvidence> Function(int count)? readBehavior;
  Future<void> Function()? refreshBehavior;

  @override
  bool get firebaseReady => ready;

  @override
  DedaRescueSnapshot snapshot() => current;

  @override
  Future<T> guardedInspection<T>(
    DedaRescueSnapshot expected,
    Future<T> Function() operation,
  ) async {
    guardedCalls++;
    expect(current.sameAs(expected), isTrue);
    return operation();
  }

  @override
  Future<DedaRescueEvidence> verifyOriginalOwner(
    DedaRescueSnapshot expected,
    String accountKey,
  ) async {
    reads++;
    expect(accountKey, anyOf(originalAccount, anotherAccount));
    return readBehavior == null
        ? DedaRescueEvidence.verified
        : readBehavior!(reads);
  }

  @override
  Future<void> refreshSamePrincipalToken(
    DedaRescueSnapshot expected,
  ) async {
    tokenRefreshes++;
    if (refreshBehavior != null) await refreshBehavior!();
  }
}

DedaSessionRecoveryCoordinator create(FakeRescuePort io) =>
    DedaSessionRecoveryCoordinator(
      port: io,
      delay: (_) async {},
    );

void main() {
  test('original server proof allows only account-scoped refresh', () async {
    final io = FakeRescuePort();
    final result = await create(io).inspectOwner(accountKey: originalAccount);
    expect(result.status, DedaRescueStatus.ready);
    expect(result.canRefreshOwnerViews, isTrue);
    expect(io.reads, 1);
    expect(io.guardedCalls, 1);
    expect(io.tokenRefreshes, 0);
  });

  test('same principal and account share one in-flight proof', () async {
    final io = FakeRescuePort();
    final remote = Completer<DedaRescueEvidence>();
    io.readBehavior = (_) => remote.future;
    final coordinator = create(io);
    final first = coordinator.inspectOwner(accountKey: originalAccount);
    final second = coordinator.inspectOwner(accountKey: originalAccount);
    expect(identical(first, second), isTrue);
    remote.complete(DedaRescueEvidence.verified);
    expect((await first).status, DedaRescueStatus.ready);
    expect(io.reads, 1);
  });

  test('concurrent other account cannot borrow original account proof', () async {
    final io = FakeRescuePort();
    final remote = Completer<DedaRescueEvidence>();
    io.readBehavior = (_) => remote.future;
    final coordinator = create(io);
    final first = coordinator.inspectOwner(accountKey: originalAccount);
    final second = await coordinator.inspectOwner(accountKey: anotherAccount);
    expect(second.status, DedaRescueStatus.temporarilyBusy);
    expect(second.canRefreshOwnerViews, isFalse);
    remote.complete(DedaRescueEvidence.verified);
    await first;
    expect(io.reads, 1);
  });

  test('network failure is retried at most once and never becomes proof', () async {
    final io = FakeRescuePort();
    io.readBehavior = (_) async => DedaRescueEvidence.temporaryNetworkFailure;
    final result = await create(io).inspectOwner(accountKey: originalAccount);
    expect(result.status, DedaRescueStatus.temporarilyOffline);
    expect(result.canRefreshOwnerViews, isFalse);
    expect(io.reads, 2);
    expect(io.tokenRefreshes, 0);
  });

  test('one transient read then server verified succeeds', () async {
    final io = FakeRescuePort();
    io.readBehavior = (calls) async => calls == 1
        ? DedaRescueEvidence.temporaryNetworkFailure
        : DedaRescueEvidence.verified;
    final result = await create(io).inspectOwner(accountKey: originalAccount);
    expect(result.status, DedaRescueStatus.ready);
    expect(io.reads, 2);
  });

  test('a denied Firestore permission is not retried or bypassed', () async {
    final io = FakeRescuePort();
    io.readBehavior = (_) async => DedaRescueEvidence.permissionDenied;
    final result = await create(io).inspectOwner(accountKey: originalAccount);
    expect(result.status, DedaRescueStatus.permissionDenied);
    expect(result.canRefreshOwnerViews, isFalse);
    expect(io.reads, 1);
  });

  test('missing ownership proof cannot trigger credential refresh', () async {
    final io = FakeRescuePort();
    io.readBehavior = (_) async => DedaRescueEvidence.ownerProofRequired;
    final result = await create(io).inspectOwner(accountKey: originalAccount);
    expect(result.status, DedaRescueStatus.ownerProofRequired);
    expect(io.reads, 1);
    expect(io.tokenRefreshes, 0);
  });

  test('an explicit expired-token signal allows one same-principal refresh', () async {
    final io = FakeRescuePort();
    io.readBehavior = (calls) async => calls == 1
        ? DedaRescueEvidence.tokenExpired
        : DedaRescueEvidence.verified;
    final result = await create(io).inspectOwner(accountKey: originalAccount);
    expect(result.status, DedaRescueStatus.ready);
    expect(io.tokenRefreshes, 1);
    expect(io.reads, 2);
  });

  test('token refresh is bounded when credential remains expired', () async {
    final io = FakeRescuePort();
    io.readBehavior = (_) async => DedaRescueEvidence.tokenExpired;
    final result = await create(io).inspectOwner(accountKey: originalAccount);
    expect(result.status, DedaRescueStatus.ownerProofRequired);
    expect(io.tokenRefreshes, 1);
    expect(io.reads, 2);
  });

  test('UID change during remote read discards a late positive answer', () async {
    final io = FakeRescuePort();
    final remote = Completer<DedaRescueEvidence>();
    io.readBehavior = (_) => remote.future;
    final coordinator = create(io);
    final first = coordinator.inspectOwner(accountKey: originalAccount);
    io.current = const DedaRescueSnapshot(
      uid: 'another-user', epoch: 8, anonymous: false,
    );
    remote.complete(DedaRescueEvidence.verified);
    final result = await first;
    expect(result.status, DedaRescueStatus.uidChanged);
    expect(result.canRefreshOwnerViews, isFalse);
  });

  test('same UID but changed epoch cannot reuse stale server approval', () async {
    final io = FakeRescuePort();
    final remote = Completer<DedaRescueEvidence>();
    io.readBehavior = (_) => remote.future;
    final resultFuture = create(io).inspectOwner(accountKey: originalAccount);
    io.current = const DedaRescueSnapshot(
      uid: 'original-immutable-uid', epoch: 9, anonymous: false,
    );
    remote.complete(DedaRescueEvidence.verified);
    expect((await resultFuture).status, DedaRescueStatus.uidChanged);
  });

  test('anonymous/account kind change invalidates server proof', () async {
    final io = FakeRescuePort();
    final remote = Completer<DedaRescueEvidence>();
    io.readBehavior = (_) => remote.future;
    final resultFuture = create(io).inspectOwner(accountKey: originalAccount);
    io.current = const DedaRescueSnapshot(
      uid: 'original-immutable-uid', epoch: 7, anonymous: true,
    );
    remote.complete(DedaRescueEvidence.verified);
    expect((await resultFuture).status, DedaRescueStatus.uidChanged);
  });

  test('sign-out and disabled Firebase cannot invent new principal', () async {
    final io = FakeRescuePort();
    io.current = const DedaRescueSnapshot(
      uid: null, epoch: 10, anonymous: false,
    );
    final coordinator = create(io);
    expect((await coordinator.inspectOwner(accountKey: originalAccount)).status,
        DedaRescueStatus.signedOut);
    io.ready = false;
    expect((await coordinator.inspectOwner(accountKey: originalAccount)).status,
        DedaRescueStatus.firebaseNotReady);
    expect(io.reads, 0);
    expect(io.tokenRefreshes, 0);
  });

  test('invalid account key is not server authorization', () async {
    final io = FakeRescuePort();
    final result = await create(io).inspectOwner(accountKey: 'not-a-phone');
    expect(result.status, DedaRescueStatus.ownerProofRequired);
    expect(io.reads, 0);
  });

  test('successful result is never cached as a permission', () async {
    final io = FakeRescuePort();
    final coordinator = create(io);
    expect((await coordinator.inspectOwner(accountKey: originalAccount)).status,
        DedaRescueStatus.ready);
    io.readBehavior = (_) async => DedaRescueEvidence.permissionDenied;
    expect((await coordinator.inspectOwner(accountKey: originalAccount)).status,
        DedaRescueStatus.permissionDenied);
    expect(io.reads, 2);
  });

  test('Firebase exception categories never accidentally grant access', () {
    expect(DedaFirebaseRescuePort.classify(
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied')),
        DedaRescueEvidence.permissionDenied);
    expect(DedaFirebaseRescuePort.classify(
        FirebaseException(plugin: 'cloud_firestore', code: 'unavailable')),
        DedaRescueEvidence.temporaryNetworkFailure);
    expect(DedaFirebaseRescuePort.classify(
        FirebaseException(plugin: 'firebase_auth', code: 'user-token-expired')),
        DedaRescueEvidence.tokenExpired);
    expect(DedaFirebaseRescuePort.classify(StateError('other')),
        DedaRescueEvidence.ownerProofRequired);
  });
}
