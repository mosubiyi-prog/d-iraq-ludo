import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'deda_auth_session_runtime.dart';
import 'deda_session_transition_gate.dart' show DedaSessionAuthKind;

/// Phase 02 laboratory only. No new Auth authority, automatic enrollment,
/// local progress, Firestore, legacy account lookup or admin session.
/// The expected UID is supplied from the explicitly provisioned lab account,
/// not learned from a phone cache or from whatever login happens to succeed.
class DedaStage02LabSingleUid {
  const DedaStage02LabSingleUid._();

  static const approvedUid = 'PLmG06Uhhheef1hDE2MLfX6DEpg2';
  static const approvedEmail = 'deda-qa-test@example.com';

  static bool matchesLab({
    required String projectId,
    required String appId,
    required String senderId,
    required String? storageBucket,
    required String appName,
    required int appCount,
  }) => projectId == 'deda-qa-uid-lab-20261108' &&
      appId == '1:180856267046:android:4c5670efc62169738121e7' &&
      senderId == '180856267046' &&
      storageBucket == 'deda-qa-uid-lab-20261108.firebasestorage.app' &&
      appName == '[DEFAULT]' && appCount == 1;

  static bool matchesPrincipal({
    required String expectedUid,
    required String? uid,
    required DedaSessionAuthKind kind,
  }) => expectedUid == approvedUid &&
      uid == expectedUid && kind == DedaSessionAuthKind.authenticated;

  static void requireLab(FirebaseApp app) {
    final o = app.options;
    if (!DedaAuthRuntime.enabled ||
        !matchesLab(projectId: o.projectId, appId: o.appId,
          senderId: o.messagingSenderId, storageBucket: o.storageBucket,
          appName: app.name, appCount: Firebase.apps.length)) {
      throw StateError('stage02-lab-project-or-shared-guardian-not-ready');
    }
  }

  /// Observe the existing SDK principal. A missing or mismatched session
  /// never creates, switches or logs out a user.
  static String? inspect({required String expectedUid}) {
    final app = Firebase.app();
    requireLab(app);
    final live = DedaAuthRuntime.capture();
    if (live == null || !matchesPrincipal(expectedUid: expectedUid,
        uid: live.uid, kind: live.kind)) return null;
    return live.uid;
  }

  /// Verification must be bound to the same authenticated SDK epoch, not
  /// merely the same UID string after an intervening sign-out or switch.
  static bool matchesVerifiedSession({
    required DedaAuthSnapshot before,
    required DedaAuthSnapshot after,
    required bool serverResponded,
  }) => serverResponded && before.matches(after) &&
      matchesPrincipal(expectedUid: approvedUid, uid: before.uid,
          kind: before.kind);

  /// Reuse the same verified-session boundary for app admission and storage.
  /// No credential creation, login, sign-out, cached proof or token persistence.
  static Future<DedaAuthSnapshot> verifyServer({required String expectedUid}) async {
    final app = Firebase.app();
    requireLab(app);
    final auth = FirebaseAuth.instanceFor(app: app);
    final before = DedaAuthRuntime.capture();
    final user = auth.currentUser;
    if (before == null || user == null ||
        user.email != approvedEmail ||
        inspect(expectedUid: expectedUid) != expectedUid) {
      throw StateError('stage02-existing-lab-session-required');
    }
    final token = await user.getIdToken(true).timeout(const Duration(seconds: 15));
    requireLab(app);
    final after = DedaAuthRuntime.capture();
    if (after == null || !matchesVerifiedSession(before: before, after: after,
          serverResponded: token != null && token.isNotEmpty) ||
        auth.currentUser?.email != approvedEmail ||
        inspect(expectedUid: expectedUid) != expectedUid) {
      throw StateError('stage02-server-session-proof-rejected');
    }
    DedaAuthRuntime.checkSnapshot(before);
    return before;
  }

  /// One explicit existing-account login through the EXISTING shared lane.
  /// Only dedicated lab account credentials, never a production phone/PIN.
  /// No automatic retry, fallback, sign-up, linking or account replacement.
  /// If the provider returns the wrong UID, the guard denies admission;
  /// the caller must keep all app sections blocked.
  static Future<String> loginExisting({
    required String expectedUid,
    required String email,
    required String password,
    required bool explicitUserAction,
  }) async {
    final app = Firebase.app();
    requireLab(app);
    if (!explicitUserAction || expectedUid != approvedUid ||
        email.trim() != approvedEmail || password.isEmpty) {
      throw StateError('stage02-explicit-lab-account-required');
    }
    final auth = FirebaseAuth.instanceFor(app: app);
    final before = DedaAuthRuntime.capture();
    if (before == null) throw StateError('stage02-shared-guardian-required');
    if (before.uid != null) {
      if (matchesPrincipal(expectedUid: expectedUid,
          uid: before.uid, kind: before.kind)) return before.uid!;
      throw StateError('stage02-existing-different-principal-preserved');
    }
    return DedaAuthRuntime.run<String>(
      kind: DedaSessionTransitionKind.ownerLogin,
      origin: DedaSessionTransitionOrigin.userAction,
      action: () async {
        requireLab(app);
        DedaAuthRuntime.checkSnapshot(before);
        if (auth.currentUser != null) {
          throw StateError('stage02-no-session-replacement');
        }
        final credential = await DedaAuthRuntime.controller.transition<UserCredential>(
          kind: DedaSessionTransitionKind.ownerLogin,
          action: () => auth.signInWithEmailAndPassword(
              email: email.trim(), password: password),
          accepts: (result, live) =>
              result.user?.uid == expectedUid &&
              result.user?.isAnonymous == false &&
              matchesPrincipal(expectedUid: expectedUid,
                uid: live.uid, kind: live.kind),
        );
        DedaAuthRuntime.check();
        requireLab(app);
        if (credential.user?.uid != expectedUid ||
            inspect(expectedUid: expectedUid) != expectedUid) {
          throw StateError('stage02-lab-uid-mismatch');
        }
        return expectedUid;
      },
    );
  }
}
