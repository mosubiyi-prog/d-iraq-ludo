import 'dart:async';

final _sessionGateZoneKey = Object();

/// SDK session shape, never proof of an account owner or an administrator role.
enum DedaSessionAuthKind { none, anonymous, authenticated }
enum DedaSessionPurpose { publicData, ownerData, adminData }
enum DedaSessionReadiness {
  firebaseNotReady,
  sessionPresent,
  needAnonymousSession,
  needOwnerProof,
  needAdminLogin,
  needAdminProof,
}

enum DedaSessionTransitionKind {
  anonymousPreparation, ownerRestore, ownerLogin, accountCreate,
  adminLogin, adminInviteActivation, credentialChange, logout,
}
enum DedaSessionTransitionOrigin { background, activeSection, userAction }
enum DedaSessionAdmission {
  allowed, backgroundMutationDenied, explicitUserActionRequired, sessionAlreadyPresent,
}

/// Observation only: these decisions never sign in/out or grant permissions.
class DedaSessionReadinessPolicy {
  static DedaSessionReadiness inspect({
    required bool firebaseReady,
    required DedaSessionAuthKind auth,
    required DedaSessionPurpose purpose,
  }) {
    if (!firebaseReady) return DedaSessionReadiness.firebaseNotReady;
    if (auth == DedaSessionAuthKind.none) {
      return purpose == DedaSessionPurpose.adminData
          ? DedaSessionReadiness.needAdminLogin
          : DedaSessionReadiness.needAnonymousSession;
    }
    switch (purpose) {
      case DedaSessionPurpose.publicData:
        return DedaSessionReadiness.sessionPresent;
      case DedaSessionPurpose.ownerData:
        // An administrator can also be a verified owner. Preserve the session
        // and ask the existing server proof; never infer that a logout is needed.
        return DedaSessionReadiness.needOwnerProof;
      case DedaSessionPurpose.adminData:
        return auth == DedaSessionAuthKind.authenticated
            ? DedaSessionReadiness.needAdminProof
            : DedaSessionReadiness.needAdminLogin;
    }
  }

  static DedaSessionAdmission admission({
    required DedaSessionTransitionKind kind,
    required DedaSessionTransitionOrigin origin,
    required DedaSessionAuthKind auth,
  }) {
    if (origin == DedaSessionTransitionOrigin.background) {
      return DedaSessionAdmission.backgroundMutationDenied;
    }
    if (origin == DedaSessionTransitionOrigin.userAction) {
      return DedaSessionAdmission.allowed;
    }
    if (kind == DedaSessionTransitionKind.anonymousPreparation) {
      if (auth == DedaSessionAuthKind.none) return DedaSessionAdmission.allowed;
      return DedaSessionAdmission.sessionAlreadyPresent;
    }
    if (kind == DedaSessionTransitionKind.ownerRestore &&
        auth == DedaSessionAuthKind.anonymous) {
      // Admission is not trusted-install/owner proof. The action must retain
      // all existing server checks before it changes deda_sessions.
      return DedaSessionAdmission.allowed;
    }
    return DedaSessionAdmission.explicitUserActionRequired;
  }
}

/// A transition action checks this before each subsequent SDK call/write and
/// before publishing. A timeout does NOT undo an SDK side effect already sent.
class DedaSessionTransitionPermit {
  DedaSessionTransitionPermit._(this._current);
  final bool Function() _current;
  bool get isCurrent => _current();
  void checkCurrent() {
    if (!isCurrent) throw const DedaStaleSessionTransition();
  }
}

/// One shared lane for explicitly admitted session transitions. No queue,
/// automatic retry, Firebase access, credential storage or logging. Different
/// intents fail busy; callers must explicitly reconcile and try again later.
/// Keep the lane occupied until the ACTUAL action future settles, even after
/// the caller's timeout, invalidation or disposal.
///
/// Not connected to the production auth paths yet. A partial primitive-only
/// integration cannot protect higher-level PIN/session/profile writes.
class DedaSessionTransitionGate {
  DedaSessionTransitionGate({this.timeout = const Duration(seconds: 12)}) {
    if (timeout <= Duration.zero) throw ArgumentError('invalid-transition-timeout');
  }

  final Duration timeout;
  _SessionPending<dynamic>? _active;
  int _generation = 0;
  bool _closed = false;
  int _started = 0;
  int _joined = 0;
  int _busy = 0;
  int _denied = 0;
  int _succeeded = 0;
  int _failed = 0;
  int _timedOut = 0;
  int _invalidated = 0;
  int _lateSettled = 0;

  Map<String, int> get diagnostics => Map.unmodifiable({
    'started': _started, 'joined': _joined, 'busy': _busy, 'denied': _denied,
    'succeeded': _succeeded, 'failed': _failed, 'timedOut': _timedOut,
    'invalidated': _invalidated, 'lateSettled': _lateSettled,
    'inFlight': _active == null ? 0 : 1,
  });

  /// Invalidate a USER INTENT (selected account, screen or explicit logout).
  /// Expected auth changes produced by the admitted login are not themselves
  /// a reason to invalidate it. Read-only identity scopes have separate epochs.
  void invalidate() {
    ++_generation;
    final entry = _active;
    if (entry != null && !entry.result.isCompleted) {
      _invalidated++;
      entry.endedEarly = true;
      entry.timer?.cancel();
      entry.result.completeError(const DedaStaleSessionTransition());
    }
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    invalidate();
  }

  Future<T> run<T>({
    required Object key,
    required DedaSessionTransitionKind kind,
    required DedaSessionTransitionOrigin origin,
    required DedaSessionAuthKind Function() currentAuthKind,
    required bool Function() isCurrent,
    required Future<T> Function(DedaSessionTransitionPermit permit) action,
  }) {
    if (_closed) return Future<T>.error(const DedaSessionGateClosed());
    // A wrapped login may call lower-level helpers. They must share its permit,
    // not await their own in-flight future or start another transition.
    if (identical(Zone.current[_sessionGateZoneKey], this)) {
      _denied++;
      return Future<T>.error(const DedaSessionTransitionReentrant());
    }
    try {
      if (!isCurrent()) return Future<T>.error(const DedaStaleSessionTransition());
      if (origin == DedaSessionTransitionOrigin.background) {
        _denied++;
        return Future<T>.error(const DedaSessionTransitionDenied(
            DedaSessionAdmission.backgroundMutationDenied));
      }
      final existing = _active;
      if (existing != null) {
        if (existing is _SessionPending<T> &&
            existing.generation == _generation && existing.key == key &&
            existing.kind == kind && existing.origin == origin) {
          _joined++;
          return existing.result.future;
        }
        _busy++;
        return Future<T>.error(const DedaSessionTransitionBusy());
      }
      final admission = DedaSessionReadinessPolicy.admission(
        kind: kind, origin: origin, auth: currentAuthKind(),
      );
      if (admission != DedaSessionAdmission.allowed) {
        _denied++;
        return Future<T>.error(DedaSessionTransitionDenied(admission));
      }
    } catch (error, stack) {
      return Future<T>.error(error, stack);
    }

    final entry = _SessionPending<T>(key, kind, origin, _generation);
    _active = entry;
    _started++;
    final permit = DedaSessionTransitionPermit._(() => !_closed &&
        entry.generation == _generation && !entry.result.isCompleted && isCurrent());
    entry.timer = Timer(timeout, () {
      if (!entry.result.isCompleted) {
        _timedOut++;
        entry.endedEarly = true;
        entry.result.completeError(TimeoutException('session-transition-wait-expired', timeout));
      }
    });
    Future<void> drive() async {
      try {
        permit.checkCurrent();
        final value = await runZoned(
          () => action(permit), zoneValues: {_sessionGateZoneKey: this},
        );
        permit.checkCurrent();
        _succeeded++;
        entry.result.complete(value);
      } catch (error, stack) {
        if (!entry.result.isCompleted) {
          if (error is DedaStaleSessionTransition) {
            _invalidated++;
          } else {
            _failed++;
          }
          entry.result.completeError(error, stack);
        }
      } finally {
        entry.timer?.cancel();
        if (entry.endedEarly) _lateSettled++;
        if (identical(_active, entry)) _active = null;
      }
    }
    unawaited(drive());
    return entry.result.future;
  }
}

class _SessionPending<T> {
  _SessionPending(this.key, this.kind, this.origin, this.generation);
  final Object key;
  final DedaSessionTransitionKind kind;
  final DedaSessionTransitionOrigin origin;
  final int generation;
  final result = Completer<T>();
  Timer? timer;
  bool endedEarly = false;
}

class DedaStaleSessionTransition implements Exception {
  const DedaStaleSessionTransition();
}
class DedaSessionTransitionBusy implements Exception {
  const DedaSessionTransitionBusy();
}
class DedaSessionTransitionReentrant implements Exception {
  const DedaSessionTransitionReentrant();
}
class DedaSessionGateClosed implements Exception {
  const DedaSessionGateClosed();
}
class DedaSessionTransitionDenied implements Exception {
  const DedaSessionTransitionDenied(this.reason);
  final DedaSessionAdmission reason;
}
