import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'deda_100431_linked_owner_session_policy.dart';
import 'deda_auth_session_runtime.dart';

/// Isolated stage-2 candidate: not wired into signed 100440.
/// No sign-in, sign-out, new UID, Google credential, permission or wallet write.
enum DedaRescueStatus {
  ready,
  firebaseNotReady,
  signedOut,
  ownerProofRequired,
  permissionDenied,
  uidChanged,
  temporarilyOffline,
  temporarilyBusy,
}

enum DedaRescueEvidence {
  verified,
  ownerProofRequired,
  permissionDenied,
  temporaryNetworkFailure,
  tokenExpired,
}

class DedaRescueSnapshot {
  const DedaRescueSnapshot({
    required this.uid,
    required this.epoch,
    required this.anonymous,
  });
  final String? uid;
  final int epoch;
  final bool anonymous;

  bool sameAs(DedaRescueSnapshot other) =>
      uid == other.uid && epoch == other.epoch &&
      anonymous == other.anonymous;
}

class DedaRescueResult {
  const DedaRescueResult(this.status);
  final DedaRescueStatus status;

  /// Does not authorize admin entry, Google linking or financial operations.
  bool get canRefreshOwnerViews => status == DedaRescueStatus.ready;
}

/// Injected transport keeps unit tests disconnected from live Firebase.
abstract class DedaRescuePort {
  bool get firebaseReady;
  DedaRescueSnapshot snapshot();
  Future<T> guardedInspection<T>(
    DedaRescueSnapshot expected,
    Future<T> Function() operation,
  );
  Future<DedaRescueEvidence> verifyOriginalOwner(
    DedaRescueSnapshot expected, String accountKey,
  );
  Future<void> refreshSamePrincipalToken(DedaRescueSnapshot expected);
}

/// Single-flight, same UID/epoch/account read coordinator.
/// No positive result is retained across calls. No background account switch.
class DedaSessionRecoveryCoordinator {
  DedaSessionRecoveryCoordinator({
    required this.port,
    Future<void> Function(Duration)? delay,
  }) : _delay = delay ?? ((duration) => Future<void>.delayed(duration));

  final DedaRescuePort port;
  final Future<void> Function(Duration) _delay;
  Future<DedaRescueResult>? _inFlight;
  String? _flightKey;

  DedaRescueSnapshot? _safeSnapshot() {
    try {
      return port.snapshot();
    } catch (_) {
      return null;
    }
  }

  bool _same(DedaRescueSnapshot expected) {
    final actual = _safeSnapshot();
    return port.firebaseReady && actual != null && expected.sameAs(actual);
  }

  Future<DedaRescueResult> inspectOwner({required String accountKey}) {
    // The local phone/key is input to server proof, never proof on its own.
    if (!RegExp(r'^[0-9]{8,16}$').hasMatch(accountKey)) {
      return Future.value(const DedaRescueResult(
          DedaRescueStatus.ownerProofRequired));
    }
    if (!port.firebaseReady) {
      return Future.value(const DedaRescueResult(
          DedaRescueStatus.firebaseNotReady));
    }
    final atStart = _safeSnapshot();
    if (atStart == null) {
      return Future.value(const DedaRescueResult(
          DedaRescueStatus.firebaseNotReady));
    }
    if (atStart.uid == null || atStart.uid!.isEmpty) {
      return Future.value(const DedaRescueResult(DedaRescueStatus.signedOut));
    }
    final key = atStart.uid! + '|' + atStart.epoch.toString() +
        '|' + atStart.anonymous.toString() + '|' + accountKey;
    final running = _inFlight;
    if (running != null) {
      if (_flightKey == key) return running;
      return Future.value(const DedaRescueResult(
          DedaRescueStatus.temporarilyBusy));
    }
    final work = _inspect(atStart, accountKey);
    _flightKey = key;
    _inFlight = work;
    // Hold until the actual IO settles; no timeout unlocks a pending call.
    unawaited(work.then<void>((_) {
      if (identical(_inFlight, work)) {
        _inFlight = null;
        _flightKey = null;
      }
    }, onError: (Object _, StackTrace __) {
      if (identical(_inFlight, work)) {
        _inFlight = null;
        _flightKey = null;
      }
    }));
    return work;
  }

  Future<DedaRescueResult> _inspect(
      DedaRescueSnapshot expected, String accountKey) async {
    if (!_same(expected)) {
      return const DedaRescueResult(DedaRescueStatus.uidChanged);
    }
    try {
      return await port.guardedInspection<DedaRescueResult>(
        expected,
        () async {
          for (var attempt = 0; attempt < 2; attempt++) {
            if (!_same(expected)) {
              return const DedaRescueResult(DedaRescueStatus.uidChanged);
            }
            DedaRescueEvidence evidence;
            try {
              evidence = await port.verifyOriginalOwner(expected, accountKey);
            } catch (error) {
              evidence = DedaFirebaseRescuePort.classify(error);
            }
            if (!_same(expected)) {
              return const DedaRescueResult(DedaRescueStatus.uidChanged);
            }
            switch (evidence) {
              case DedaRescueEvidence.verified:
                return const DedaRescueResult(DedaRescueStatus.ready);
              case DedaRescueEvidence.ownerProofRequired:
                return const DedaRescueResult(
                    DedaRescueStatus.ownerProofRequired);
              case DedaRescueEvidence.permissionDenied:
                return const DedaRescueResult(DedaRescueStatus.permissionDenied);
              case DedaRescueEvidence.temporaryNetworkFailure:
                if (attempt == 0) {
                  await _delay(const Duration(milliseconds: 400));
                  continue;
                }
                return const DedaRescueResult(
                    DedaRescueStatus.temporarilyOffline);
              case DedaRescueEvidence.tokenExpired:
                if (attempt != 0) {
                  return const DedaRescueResult(
                      DedaRescueStatus.ownerProofRequired);
                }
                try {
                  await port.refreshSamePrincipalToken(expected);
                } catch (error) {
                  if (!_same(expected)) {
                    return const DedaRescueResult(DedaRescueStatus.uidChanged);
                  }
                  final classified = DedaFirebaseRescuePort.classify(error);
                  return DedaRescueResult(
                      classified == DedaRescueEvidence.permissionDenied
                          ? DedaRescueStatus.permissionDenied
                          : DedaRescueStatus.temporarilyOffline);
                }
                continue;
            }
          }
          return const DedaRescueResult(DedaRescueStatus.temporarilyOffline);
        },
      );
    } catch (error) {
      if (!_same(expected)) {
        return const DedaRescueResult(DedaRescueStatus.uidChanged);
      }
      final classified = DedaFirebaseRescuePort.classify(error);
      return DedaRescueResult(
          classified == DedaRescueEvidence.permissionDenied
              ? DedaRescueStatus.permissionDenied
              : classified == DedaRescueEvidence.temporaryNetworkFailure
                  ? DedaRescueStatus.temporarilyOffline
                  : DedaRescueStatus.temporarilyBusy);
    }
  }
}

/// SDK read-only adapter. The existing DedaAuthRuntime inspection permit
/// owns this entire logical operation. No second auth guardian is created.
class DedaFirebaseRescuePort implements DedaRescuePort {
  const DedaFirebaseRescuePort();

  @override
  bool get firebaseReady =>
      Firebase.apps.isNotEmpty && DedaAuthRuntime.enabled;

  @override
  DedaRescueSnapshot snapshot() {
    if (!firebaseReady) throw StateError('rescue-guardian-not-enabled');
    final observed = DedaAuthRuntime.capture()!;
    final current = FirebaseAuth.instance.currentUser;
    if (current?.uid != observed.uid) {
      throw StateError('rescue-auth-observer-mismatch');
    }
    return DedaRescueSnapshot(
      uid: observed.uid,
      epoch: observed.epoch,
      anonymous: current?.isAnonymous ?? false,
    );
  }

  void _requireUnchanged(DedaRescueSnapshot expected) {
    if (!snapshot().sameAs(expected)) {
      throw StateError('rescue-principal-changed');
    }
  }

  @override
  Future<T> guardedInspection<T>(
      DedaRescueSnapshot expected, Future<T> Function() operation) {
    final captured = DedaAuthRuntime.capture();
    if (captured == null || captured.uid != expected.uid ||
        captured.epoch != expected.epoch) {
      throw StateError('rescue-auth-epoch-mismatch');
    }
    return DedaAuthRuntime.forSnapshot<T>(
      captured,
      kind: DedaSessionTransitionKind.sessionInspection,
      origin: DedaSessionTransitionOrigin.activeSection,
      action: () async {
        _requireUnchanged(expected);
        final result = await operation();
        _requireUnchanged(expected);
        return result;
      },
    );
  }

  @override
  Future<DedaRescueEvidence> verifyOriginalOwner(
      DedaRescueSnapshot expected, String accountKey) async {
    _requireUnchanged(expected);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return DedaRescueEvidence.ownerProofRequired;
    // A non-anonymous staff member cannot impersonate an ordinary owner.
    if (!user.isAnonymous &&
        !DedaLinkedOwnerSessionPolicy.userProviderIdentityMatches(
            user, accountKey)) {
      return DedaRescueEvidence.ownerProofRequired;
    }
    final db = FirebaseFirestore.instance;
    const server = GetOptions(source: Source.server);
    final rows = await Future.wait([
      db.collection('deda_account_directory').doc(accountKey).get(server),
      db.collection('deda_sessions').doc(expected.uid).get(server),
      db.collection('users').doc(expected.uid).get(server),
    ]);
    _requireUnchanged(expected);
    if (rows.any((row) =>
        row.metadata.isFromCache || row.metadata.hasPendingWrites)) {
      return DedaRescueEvidence.temporaryNetworkFailure;
    }
    final directory = rows[0].data();
    final session = rows[1].data();
    final projection = rows[2].data();
    final originalId = projection?['sharePersonalId'];
    if (originalId is! String || originalId.isEmpty) {
      return DedaRescueEvidence.ownerProofRequired;
    }
    final route = await db.collection('deda_share_ids')
        .doc(originalId).get(server);
    _requireUnchanged(expected);
    if (route.metadata.isFromCache || route.metadata.hasPendingWrites) {
      return DedaRescueEvidence.temporaryNetworkFailure;
    }
    final valid = DedaLinkedOwnerSessionPolicy.ownerDocumentsMatch(
      uid: expected.uid!,
      accountKey: accountKey,
      directory: directory,
      session: session,
      projection: projection,
      route: route.data(),
    );
    return valid
        ? DedaRescueEvidence.verified
        : DedaRescueEvidence.ownerProofRequired;
  }

  @override
  Future<void> refreshSamePrincipalToken(
      DedaRescueSnapshot expected) async {
    _requireUnchanged(expected);
    final user = FirebaseAuth.instance.currentUser;
    if (user?.uid != expected.uid) {
      throw StateError('rescue-uid-changed-before-token-refresh');
    }
    await user!.getIdToken(true);
    _requireUnchanged(expected);
  }

  static DedaRescueEvidence classify(Object error) {
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return DedaRescueEvidence.permissionDenied;
        case 'unauthenticated':
        case 'invalid-user-token':
        case 'user-token-expired':
          return DedaRescueEvidence.tokenExpired;
        case 'unavailable':
        case 'deadline-exceeded':
        case 'network-request-failed':
          return DedaRescueEvidence.temporaryNetworkFailure;
        default:
          return DedaRescueEvidence.ownerProofRequired;
      }
    }
    if (error is TimeoutException) {
      return DedaRescueEvidence.temporaryNetworkFailure;
    }
    // Never grant permissions from an unrecognized exception.
    return DedaRescueEvidence.ownerProofRequired;
  }
}
