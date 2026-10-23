import 'deda_session_transition_gate.dart';

/// Unwired flow prototype. No Firebase adapter, credentials persistence or
/// production callsites. The port must implement the existing server rules;
/// these data classes and local policy do not grant authorization.
class DedaFlowSdkUser {
  const DedaFlowSdkUser(this.uid, this.kind, this.revision);
  final String uid;
  final DedaSessionAuthKind kind;
  /// Observed SDK principal epoch, including A -> B -> A transitions.
  final int revision;
}

class DedaOwnerSessionProof {
  const DedaOwnerSessionProof({required this.uid, required this.accountKey,
    required this.ownerVerified, required this.trustedInstallation});
  final String uid;
  final String accountKey;
  final bool ownerVerified;
  final bool trustedInstallation;
}

class DedaOwnerFlowProfile {
  const DedaOwnerFlowProfile({required this.uid, required this.accountKey,
    required this.name, required this.phone, required this.accountType});
  final String uid;
  final String accountKey;
  final String name;
  final String phone;
  final String accountType;
}

class DedaAdminSessionProof {
  const DedaAdminSessionProof({required this.uid, required this.active, required this.role});
  final String uid;
  final bool active;
  final String role;
}

class DedaOwnerFlowResult {
  const DedaOwnerFlowResult(this.user, this.proof, this.profile);
  final DedaFlowSdkUser user;
  final DedaOwnerSessionProof proof;
  final DedaOwnerFlowProfile? profile;
}

class DedaAdminFlowResult {
  const DedaAdminFlowResult(this.user, this.proof);
  final DedaFlowSdkUser user;
  final DedaAdminSessionProof proof;
}

/// All asynchronous helpers inherit the same permit. An adapter checks it
/// after local preparation awaits and BEFORE dispatching each next write.
/// Already dispatched SDK/Firestore effects cannot be cancelled by this token.
abstract class DedaSessionFlowPort {
  bool get firebaseReady;
  DedaFlowSdkUser? get currentUser;
  Future<bool> signOutIfCurrent(DedaSessionTransitionPermit permit, DedaFlowSdkUser expected);
  Future<DedaFlowSdkUser> signInAnonymous(DedaSessionTransitionPermit permit);
  Future<void> provePin(DedaSessionTransitionPermit permit, DedaFlowSdkUser user, String accountKey, String pin);
  Future<void> writeOwnerSession(DedaSessionTransitionPermit permit, DedaFlowSdkUser user, String accountKey, {required bool trustedRestore});
  Future<DedaOwnerSessionProof> readOwnerProof(DedaSessionTransitionPermit permit, DedaFlowSdkUser user, String accountKey);
  Future<DedaOwnerFlowProfile> readOwnerProfile(DedaSessionTransitionPermit permit, DedaFlowSdkUser user, String accountKey);
  Future<void> trustOwnerDevice(DedaSessionTransitionPermit permit, DedaFlowSdkUser user, String accountKey);
  Future<void> writeOwnerProjection(DedaSessionTransitionPermit permit, DedaFlowSdkUser user, DedaOwnerFlowProfile profile);
  Future<void> rememberKnownOwner(DedaSessionTransitionPermit permit, String accountKey);
  Future<DedaFlowSdkUser> signInAdmin(DedaSessionTransitionPermit permit, String email, String password);
  Future<DedaAdminSessionProof> readAdminProof(DedaSessionTransitionPermit permit, DedaFlowSdkUser user);
  Future<void> refreshAdminProfile(DedaSessionTransitionPermit permit, DedaFlowSdkUser user, DedaAdminSessionProof proof);
  Future<void> registerAdminNotifications(DedaSessionTransitionPermit permit, DedaFlowSdkUser user);
  Future<void> writeAdminAudit(DedaSessionTransitionPermit permit, DedaFlowSdkUser user, DedaAdminSessionProof proof);
}

class DedaSessionFlowPrototype {
  DedaSessionFlowPrototype({required this.port, required this.gate});
  final DedaSessionFlowPort port;
  /// The same instance must be shared by owner and administration flows.
  final DedaSessionTransitionGate gate;

  void _ready(DedaSessionTransitionPermit permit) {
    permit.checkCurrent();
    if (!port.firebaseReady) throw StateError('firebase-not-ready');
  }

  void _check(DedaSessionTransitionPermit permit, DedaFlowSdkUser user) {
    _ready(permit);
    final live = port.currentUser;
    if (user.uid.isEmpty || user.revision < 0 ||
        user.kind == DedaSessionAuthKind.none || live == null ||
        live.uid != user.uid || live.kind != user.kind || live.revision != user.revision) {
      throw const DedaStaleSessionTransition();
    }
  }

  Future<T> _step<T>(DedaSessionTransitionPermit permit, DedaFlowSdkUser user,
      Future<T> Function() action) async {
    _check(permit, user);
    final value = await action();
    _check(permit, user);
    return value;
  }

  Future<void> _signOut(DedaSessionTransitionPermit permit, DedaFlowSdkUser user) async {
    _check(permit, user);
    final ended = await port.signOutIfCurrent(permit, user);
    _ready(permit);
    if (!ended || port.currentUser != null) throw const DedaStaleSessionTransition();
  }

  Future<DedaFlowSdkUser> _anonymous(DedaSessionTransitionPermit permit,
      DedaSessionTransitionOrigin origin) async {
    _ready(permit);
    final current = port.currentUser;
    if (current != null && current.kind == DedaSessionAuthKind.anonymous) {
      _check(permit, current);
      return current;
    }
    if (current != null) {
      if (origin != DedaSessionTransitionOrigin.userAction) {
        throw const DedaSessionTransitionDenied(DedaSessionAdmission.explicitUserActionRequired);
      }
      await _signOut(permit, current);
    }
    _ready(permit);
    final user = await port.signInAnonymous(DedaSessionTransitionPermit permit);
    _check(permit, user);
    if (user.kind != DedaSessionAuthKind.anonymous) throw const DedaSessionProofRejected();
    return user;
  }

  void _ownerProof(DedaOwnerSessionProof proof, DedaFlowSdkUser user,
      String accountKey, {required bool restore}) {
    if (!proof.ownerVerified || proof.uid != user.uid || proof.accountKey != accountKey ||
        (restore && !proof.trustedInstallation)) {
      throw const DedaSessionProofRejected();
    }
  }

  Future<T> _run<T>({required DedaSessionTransitionKind kind,
    required DedaSessionTransitionOrigin origin, required bool Function() isCurrent,
    required Future<T> Function(DedaSessionTransitionPermit) action}) {
    if (!port.firebaseReady) return Future<T>.error(StateError('firebase-not-ready'));
    return gate.run<T>(
      // Each invocation is a new intent, so different PINs/passwords cannot
      // merge accidentally. Repeated taps fail busy, without retaining a PIN
      // in a deduplication key or starting a second SDK operation.
      key: Object(), kind: kind, origin: origin,
      currentAuthKind: () => port.currentUser?.kind ?? DedaSessionAuthKind.none,
      isCurrent: isCurrent, action: action,
    );
  }

  Future<DedaOwnerFlowResult> ownerLogin({required String accountKey, required String pin,
    required DedaSessionTransitionOrigin origin, required bool Function() isCurrent}) {
    final account = accountKey.trim();
    if (account.isEmpty || !RegExp(r'^\d{6}$').hasMatch(pin)) {
      return Future<DedaOwnerFlowResult>.error(ArgumentError('invalid-owner-input'));
    }
    return _run(kind: DedaSessionTransitionKind.ownerLogin, origin: origin,
      isCurrent: isCurrent, action: (permit) async {
        final user = await _anonymous(permit, origin);
        await _step(permit, user, () => port.provePin(permit, user, account, pin));
        await _step(permit, user, () => port.writeOwnerSession(permit, user, account, trustedRestore: false));
        final proof = await _step(permit, user, () => port.readOwnerProof(permit, user, account));
        _ownerProof(proof, user, account, restore: false);
        final profile = await _step(permit, user, () => port.readOwnerProfile(permit, user, account));
        if (profile.uid != user.uid || profile.accountKey != account || profile.name.trim().isEmpty) {
          throw const DedaSessionProofRejected();
        }
        await _step(permit, user, () => port.trustOwnerDevice(permit, user, account));
        await _step(permit, user, () => port.writeOwnerProjection(permit, user, profile));
        await _step(permit, user, () => port.rememberKnownOwner(permit, account));
        _check(permit, user);
        return DedaOwnerFlowResult(user, proof, profile);
      });
  }

  Future<DedaOwnerFlowResult> restoreOwner({required String accountKey,
    required DedaSessionTransitionOrigin origin, required bool Function() isCurrent}) {
    final account = accountKey.trim();
    if (account.isEmpty) return Future<DedaOwnerFlowResult>.error(ArgumentError('empty-account-key'));
    return _run(kind: DedaSessionTransitionKind.ownerRestore, origin: origin,
      isCurrent: isCurrent, action: (permit) async {
        final user = await _anonymous(permit, origin);
        await _step(permit, user, () => port.writeOwnerSession(permit, user, account, trustedRestore: true));
        final proof = await _step(permit, user, () => port.readOwnerProof(permit, user, account));
        _ownerProof(proof, user, account, restore: true);
        _check(permit, user);
        // Trusted restore must not silently rewrite a profile or trust a new device.
        return DedaOwnerFlowResult(user, proof, null);
      });
  }

  Future<DedaAdminFlowResult> adminLogin({required String email, required String password,
    required DedaSessionTransitionOrigin origin, required bool Function() isCurrent}) {
    if (email.trim().isEmpty || password.isEmpty) {
      return Future<DedaAdminFlowResult>.error(ArgumentError('invalid-admin-input'));
    }
    return _run(kind: DedaSessionTransitionKind.adminLogin, origin: origin,
      isCurrent: isCurrent, action: (permit) async {
        _ready(permit);
        final user = await port.signInAdmin(permit, email.trim(), password);
        _check(permit, user);
        if (user.kind != DedaSessionAuthKind.authenticated) throw const DedaSessionProofRejected();
        final proof = await _step(permit, user, () => port.readAdminProof(permit, user));
        if (proof.uid != user.uid) throw const DedaSessionProofRejected();
        if (!proof.active || proof.role.trim().isEmpty) {
          // Only this still-current principal may be signed out after rejection.
          await _signOut(permit, user);
          throw const DedaSessionProofRejected();
        }
        await _step(permit, user, () => port.refreshAdminProfile(permit, user, proof));
        _check(permit, user);
        try {
          await port.registerAdminNotifications(permit, user);
        } catch (_) {
          // Preserve the existing non-fatal FCM policy. Recheck the permit/UID
          // even if the notification request failed or completed very late.
        }
        _check(permit, user);
        await _step(permit, user, () => port.writeAdminAudit(permit, user, proof));
        return DedaAdminFlowResult(user, proof);
      });
  }
}

class DedaSessionProofRejected implements Exception {
  const DedaSessionProofRejected();
}
