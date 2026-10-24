import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'deda_session_transition_gate.dart';
export 'deda_session_transition_gate.dart' show DedaSessionTransitionKind, DedaSessionTransitionOrigin;

const dedaAuthSessionRuntimeEnabled = bool.fromEnvironment(
  'DEDA_STABILITY_AUTH_RUNTIME', defaultValue: false);
final _authContextKey = Object();

/// An observed SDK epoch, including signed-out A -> B -> A transitions.
/// This is concurrency evidence only, never an owner/admin permission.
class DedaAuthSnapshot {
  const DedaAuthSnapshot(this.uid, this.kind, this.epoch);
  final String? uid;
  final DedaSessionAuthKind kind;
  final int epoch;
  bool matches(DedaAuthSnapshot other) => uid == other.uid &&
    kind == other.kind && epoch == other.epoch;
}

class _AuthContext {
  _AuthContext(this.controller, this.permit, this.origin, this.expected);
  final DedaAuthSessionController controller;
  final DedaSessionTransitionPermit permit;
  final DedaSessionTransitionOrigin origin;
  DedaAuthSnapshot expected;
  void check() {
    permit.checkCurrent();
    if (!expected.matches(controller.current())) {
      throw const DedaStaleSessionTransition();
    }
  }
}

/// One lane for COMPLETE logical flows; delegated helpers inherit its permit.
/// No retry/queue, timeout rollback, credential keys or diagnostics with PII.
class DedaAuthSessionController {
  DedaAuthSessionController({required this.current,
    Duration timeout = const Duration(seconds: 12)})
    : gate = DedaSessionTransitionGate(timeout: timeout);
  final DedaAuthSnapshot Function() current;
  final DedaSessionTransitionGate gate;
  _AuthContext? get _context {
    final value = Zone.current[_authContextKey];
    return value is _AuthContext && identical(value.controller, this) ? value : null;
  }
  void check() => _context?.check();
  void checkSnapshot(DedaAuthSnapshot snapshot) {
    if (!snapshot.matches(current())) throw const DedaStaleSessionTransition();
  }
  Future<T> run<T>({required DedaSessionTransitionKind kind,
    required DedaSessionTransitionOrigin origin,
    required Future<T> Function() action, bool Function()? isCurrent}) async {
    final inherited = _context;
    if (inherited != null) {
      inherited.check();
      if (isCurrent != null && !isCurrent()) throw const DedaStaleSessionTransition();
      final result = await action();
      inherited.check();
      if (isCurrent != null && !isCurrent()) throw const DedaStaleSessionTransition();
      return result;
    }
    return gate.run<T>(key: Object(), kind: kind, origin: origin,
      currentAuthKind: () => current().kind, isCurrent: isCurrent ?? () => true,
      action: (permit) async {
        final context = _AuthContext(this, permit, origin, current());
        return runZoned(() async {
          context.check();
          final result = await action();
          context.check();
          return result;
        }, zoneValues: {_authContextKey: context});
      });
  }
  Future<T> wait<T>(FutureOr<T> Function() action) async {
    final context = _context;
    context?.check();
    try {
      final result = await action();
      context?.check();
      return result;
    } catch (_) {
      context?.check();
      rethrow;
    }
  }
  Future<T> transition<T>({required DedaSessionTransitionKind kind,
    required Future<T> Function() action,
    required bool Function(T result, DedaAuthSnapshot live) accepts}) async {
    final context = _context;
    if (context == null) throw StateError('auth-transition-outside-shared-lane');
    context.check();
    final admission = DedaSessionReadinessPolicy.admission(kind: kind,
      origin: context.origin, auth: current().kind);
    if (admission != DedaSessionAdmission.allowed) throw DedaSessionTransitionDenied(admission);
    // Keep the lane until this ORIGINAL SDK Future settles, even if UI expires.
    final result = await action();
    context.permit.checkCurrent();
    final live = current();
    if (!accepts(result, live)) throw const DedaStaleSessionTransition();
    context.expected = live; // Adopt only the identity produced by this operation.
    context.check();
    return result;
  }
}

/// Default-off source binding. All generated auth callsites use this singleton.
class DedaAuthRuntime {
  static DedaAuthSessionController? _controller;
  static StreamSubscription<User?>? _subscription;
  static bool _observing = true;
  static String? _uid;
  static DedaSessionAuthKind _kind = DedaSessionAuthKind.none;
  static int _epoch = 0;
  static bool get enabled => dedaAuthSessionRuntimeEnabled;
  static void _observe(User? user) {
    final kind = user == null ? DedaSessionAuthKind.none : user.isAnonymous
      ? DedaSessionAuthKind.anonymous : DedaSessionAuthKind.authenticated;
    if (_uid != user?.uid || _kind != kind) { _uid = user?.uid; _kind = kind; _epoch++; }
  }
  static DedaAuthSnapshot _current() {
    if (!_observing) throw StateError('auth-observer-unavailable');
    if (Firebase.apps.isNotEmpty) {
      final auth = FirebaseAuth.instance;
      _observe(auth.currentUser);
      _subscription ??= auth.authStateChanges().listen(_observe,
        onError: (Object _, StackTrace stack) { _observing = false; },
        onDone: () { _observing = false; });
    } else { _observe(null); }
    return DedaAuthSnapshot(_uid, _kind, _epoch);
  }
  static DedaAuthSessionController get controller =>
    _controller ??= DedaAuthSessionController(current: _current);
  static Future<T> run<T>({required DedaSessionTransitionKind kind,
    DedaSessionTransitionOrigin origin = DedaSessionTransitionOrigin.userAction,
    required Future<T> Function() action, bool Function()? isCurrent}) => enabled
      ? controller.run(kind: kind, origin: origin, action: action, isCurrent: isCurrent)
      : action();
  static Future<T> wait<T>(FutureOr<T> Function() action) => enabled
    ? controller.wait(action) : Future<T>.sync(action);
  static void check() { if (enabled) controller.check(); }
  static DedaAuthSnapshot? capture() => enabled ? controller.current() : null;
  static void checkSnapshot(DedaAuthSnapshot? value) {
    if (enabled && value != null) controller.checkSnapshot(value);
  }
  static Future<T> forSnapshot<T>(DedaAuthSnapshot? snapshot, {
    required DedaSessionTransitionKind kind, required Future<T> Function() action,
    bool Function()? isCurrent}) => run(kind: kind, isCurrent: isCurrent, action: () async {
      checkSnapshot(snapshot);
      return action();
    });
  static Future<UserCredential> anonymous(FirebaseAuth auth) => !enabled
    ? auth.signInAnonymously() : controller.transition(
      kind: DedaSessionTransitionKind.anonymousPreparation, action: auth.signInAnonymously,
      accepts: (result, live) => result.user != null && result.user!.uid == live.uid &&
        live.kind == DedaSessionAuthKind.anonymous);
  static Future<UserCredential> email(FirebaseAuth auth, {
    required String email, required String password}) => !enabled
      ? auth.signInWithEmailAndPassword(email: email, password: password)
      : controller.transition(kind: DedaSessionTransitionKind.adminLogin,
        action: () => auth.signInWithEmailAndPassword(email: email, password: password),
        accepts: (result, live) => result.user != null && result.user!.uid == live.uid &&
          live.kind == DedaSessionAuthKind.authenticated);
  static Future<UserCredential> createAdmin(FirebaseAuth auth, {
    required String email, required String password}) => !enabled
      ? auth.createUserWithEmailAndPassword(email: email, password: password)
      : controller.transition(kind: DedaSessionTransitionKind.adminInviteActivation,
        action: () => auth.createUserWithEmailAndPassword(email: email, password: password),
        accepts: (result, live) => result.user != null && result.user!.uid == live.uid &&
          live.kind == DedaSessionAuthKind.authenticated);
  static Future<void> signOut(FirebaseAuth auth) => !enabled ? auth.signOut()
    : controller.transition<void>(kind: DedaSessionTransitionKind.logout,
      action: auth.signOut, accepts: (_, live) => live.uid == null);
  static Future<void> deleteUser(User user) => !enabled ? user.delete()
    : controller.transition<void>(kind: DedaSessionTransitionKind.adminInviteActivation,
      action: () async {
        if (controller.current().uid != user.uid) throw const DedaStaleSessionTransition();
        await user.delete();
      }, accepts: (_, live) => live.uid == null);
}
