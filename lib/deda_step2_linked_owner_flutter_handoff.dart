// DEDA 100436: dormant, explicit same-UID login handoff; private development.
// Existing Auth runtime provides the session lane. No new session gate.
const bool dedaLinkedFlutterHandoffEnabled = bool.fromEnvironment(
  'DEDA_LINKED_OWNER_HANDOFF', defaultValue: false);

enum DedaLoginKind { absent, anonymous, linked }

class DedaLoginIdentity {
  const DedaLoginIdentity(this.uid, this.email, this.kind, this.epoch);
  final String? uid, email;
  final DedaLoginKind kind;
  final int epoch;
}

abstract class DedaLoginHandoffPort {
  DedaLoginIdentity current();
  Future<T> inExistingOwnerLane<T>(Future<T> Function() work,
      bool Function() isCurrentIntent);
  Future<DedaLoginIdentity> signInOriginal(String account, String pin);
  Future<void> proveOriginal(String account, String originalId, String uid);
  Future<String> installId();
  Future<bool> grantDevice(String account, String originalId, String uid,
      String installId);
  Future<void> writeSession(String account, String uid, String installId);
  Future<bool> readbackSession(String account, String uid);
}

class DedaLoginHandoff {
  const DedaLoginHandoff(this.port, {this.enabled = dedaLinkedFlutterHandoffEnabled});
  final DedaLoginHandoffPort port;
  final bool enabled;

  Future<String> login({
    required String phone,
    required String pin,
    required String originalId,
    required bool explicitUserAction,
    required bool Function() isCurrentIntent,
    bool explicitReplaceAnonymous = false,
  }) async {
    if (!enabled || !explicitUserAction) throw StateError('login-handoff-inactive');
    final account = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (!RegExp(r'^[0-9]{10,16}$').hasMatch(account) ||
        !RegExp(r'^\d{6}$').hasMatch(pin) ||
        !RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(originalId)) {
      throw ArgumentError('invalid-login-input');
    }
    if (!isCurrentIntent()) throw StateError('stale-login-intent');
    final prior = port.current();
    if (prior.kind == DedaLoginKind.linked ||
        (prior.kind == DedaLoginKind.anonymous && !explicitReplaceAnonymous)) {
      throw StateError('existing-session-needs-explicit-choice');
    }
    return port.inExistingOwnerLane<String>(() async {
      void checkIntent() {
        if (!isCurrentIntent()) throw StateError('stale-login-intent');
      }
      checkIntent();
      final now = port.current();
      if (now.uid != prior.uid || now.kind != prior.kind ||
          now.epoch != prior.epoch) throw StateError('principal-changed');
      final proof = await port.signInOriginal(account, pin);
      checkIntent();
      final uid = proof.uid;
      if (uid == null || uid.isEmpty || proof.kind != DedaLoginKind.linked ||
          proof.email != '$account@deda-login.invalid') {
        throw StateError('linked-original-login-not-proven');
      }
      void checkOwner() {
        checkIntent();
        final live = port.current();
        if (live.uid != uid || live.epoch != proof.epoch ||
            live.kind != DedaLoginKind.linked || live.email != proof.email) {
          throw StateError('linked-owner-uid-changed');
        }
      }
      checkOwner();
      await port.proveOriginal(account, originalId, uid);
      checkOwner();
      final install = await port.installId();
      checkOwner();
      if (!RegExp(r'^[0-9a-f]{48}$').hasMatch(install)) {
        throw StateError('invalid-existing-install');
      }
      if (!await port.grantDevice(account, originalId, uid, install)) {
        throw StateError('server-device-grant-not-approved');
      }
      checkOwner();
      await port.writeSession(account, uid, install);
      checkOwner();
      final success = await port.readbackSession(account, uid);
      checkOwner();
      if (!success) throw StateError('server-session-readback-not-proven');
      return uid;
    }, isCurrentIntent);
  }
}
