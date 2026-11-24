import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'deda_auth_session_runtime.dart';
import 'deda_session_transition_gate.dart' show DedaSessionAuthKind;

/// Phase 2 is opt-in. The legacy published account and administrative login
/// remain untouched until full local DEDA enrollment and map/admin QA passes.
const bool dedaStableGoogleLoginEnabled = bool.fromEnvironment(
  'DEDA_STABILITY_GOOGLE_LOGIN', defaultValue: false,
);

enum DedaGoogleLoginAdmission {
  startFresh,
  reuseExistingGoogle,
  explicitAnonymousReplacementRequired,
  explicitLocalDedaReplacementRequired,
  existingPasswordOrAdminSessionPreserved,
}

class DedaStableGoogleLoginPolicy {
  const DedaStableGoogleLoginPolicy._();

  static DedaGoogleLoginAdmission admission({
    required String? currentUid,
    required bool currentIsAnonymous,
    required bool hasVerifiedGoogleProvider,
    required bool explicitAnonymousReplacement,
    bool hasRememberedDedaLogin = false,
  }) {
    if (currentUid == null || currentUid.trim().isEmpty) {
      // FirebaseAuth may be empty even though the old DEDA phone login
      // remains locally remembered. Never fence it off without consent.
      return hasRememberedDedaLogin && !explicitAnonymousReplacement
          ? DedaGoogleLoginAdmission.explicitLocalDedaReplacementRequired
          : DedaGoogleLoginAdmission.startFresh;
    }
    if (!currentIsAnonymous && hasVerifiedGoogleProvider) {
      return DedaGoogleLoginAdmission.reuseExistingGoogle;
    }
    // Password/admin sessions must never be replaced just because a user
    // opened the DEDA Google card. A separate account-switch flow is required.
    if (!currentIsAnonymous) {
      return DedaGoogleLoginAdmission.existingPasswordOrAdminSessionPreserved;
    }
    return explicitAnonymousReplacement
        ? DedaGoogleLoginAdmission.startFresh
        : DedaGoogleLoginAdmission.explicitAnonymousReplacementRequired;
  }

  static bool isSameAuthenticatedGooglePrincipal({
    required String expectedUid,
    required String? actualUid,
    required bool actualIsAnonymous,
    required Iterable<String> providerIds,
  }) => expectedUid.isNotEmpty &&
      actualUid == expectedUid &&
      !actualIsAnonymous &&
      providerIds.contains('google.com');

  /// The app has NO authorized DEDA enrollment for a fresh Google UID yet.
  /// A missing/stale local marker is never permission to display the old DEDA
  /// profile while Google Auth is already the live Firebase principal.
  static bool mustQuarantineGooglePrincipal({
    required String? currentUid,
    required bool currentIsAnonymous,
    required Iterable<String> providerIds,
  }) => currentUid != null &&
      isSameAuthenticatedGooglePrincipal(
        expectedUid: currentUid,
        actualUid: currentUid,
        actualIsAnonymous: currentIsAnonymous,
        providerIds: providerIds,
      );
}

abstract class DedaGoogleCredentialProvider {
  Future<OAuthCredential?> chooseCredential();
}

/// Native Google selection, with cancellation before ANY FirebaseAuth change.
/// Uses the known Android Google Sign-In SDK; no fake email/PIN auth.
class DedaAndroidGoogleCredentialProvider implements DedaGoogleCredentialProvider {
  DedaAndroidGoogleCredentialProvider({GoogleSignIn? googleSignIn})
      : _googleSignIn = googleSignIn ?? GoogleSignIn(scopes: <String>['email']);
  final GoogleSignIn _googleSignIn;

  @override
  Future<OAuthCredential?> chooseCredential() async {
    final selection = await _googleSignIn.signIn();
    if (selection == null) return null;
    final tokens = await selection.authentication;
    if (tokens.idToken == null || tokens.idToken!.isEmpty) {
      throw StateError('deda-google-id-token-missing');
    }
    return GoogleAuthProvider.credential(
      idToken: tokens.idToken, accessToken: tokens.accessToken,
    );
  }
}

class DedaGoogleIdentityResult {
  const DedaGoogleIdentityResult._(this.uid, this.cancelled, this.reused);
  final String? uid;
  final bool cancelled;
  final bool reused;
  factory DedaGoogleIdentityResult.cancelled() =>
      const DedaGoogleIdentityResult._(null, true, false);
  factory DedaGoogleIdentityResult.verified(String uid, {bool reused = false}) =>
      DedaGoogleIdentityResult._(uid, false, reused);
}

/// Changes only the DEFAULT FirebaseAuth principal after a direct user
/// action. It neither writes Firestore nor grants owner/admin privileges.
/// Google authentication is not authorization to the legacy A/B/C records.
class DedaStableGoogleLogin {
  DedaStableGoogleLogin({
    FirebaseAuth? auth,
    DedaGoogleCredentialProvider? credentialProvider,
    bool enabled = dedaStableGoogleLoginEnabled,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _credentialProvider = credentialProvider ??
           DedaAndroidGoogleCredentialProvider(),
       _enabled = enabled;

  final FirebaseAuth _auth;
  final DedaGoogleCredentialProvider _credentialProvider;
  final bool _enabled;
  bool _busy = false;

  static const String verifiedUidKey = 'deda_stable_google_verified_uid_v1';

  /// An authenticated Google UID is not yet an enrolled DEDA phone/profile.
  /// This is ONLY a quarantine decision: it does not grant any profile,
  /// admin or legacy A/B/C ownership. Check the LIVE Firebase principal
  /// even if the local marker was never committed (process kill/storage error).
  static Future<String?> pendingGoogleUid() async {
    if (Firebase.apps.isEmpty) return null;
    final live = FirebaseAuth.instance.currentUser;
    if (!DedaStableGoogleLoginPolicy.mustQuarantineGooglePrincipal(
      currentUid: live?.uid,
      currentIsAnonymous: live?.isAnonymous ?? true,
      providerIds: live?.providerData.map((p) => p.providerId) ??
          const <String>[],
    )) {
      return null;
    }
    return live!.uid;
  }

  /// Only an explicit pending-page exit may clear this exact Google principal.
  static Future<void> signOutPending(String expectedUid) async {
    if (!dedaStableGoogleLoginEnabled || !DedaAuthRuntime.enabled ||
        Firebase.apps.isEmpty) {
      throw StateError('deda-google-requires-default-auth-guardian');
    }
    final auth = FirebaseAuth.instance;
    final snapshot = DedaAuthRuntime.capture();
    await DedaAuthRuntime.run<void>(
      kind: DedaSessionTransitionKind.logout,
      origin: DedaSessionTransitionOrigin.userAction,
      action: () async {
        DedaAuthRuntime.checkSnapshot(snapshot);
        final pending = await pendingGoogleUid();
        DedaAuthRuntime.check();
        if (pending != expectedUid || auth.currentUser?.uid != expectedUid) {
          throw StateError('deda-stage2-pending-google-identity-changed');
        }
        await DedaAuthRuntime.signOut(auth);
        DedaAuthRuntime.check();
        final prefs = await SharedPreferences.getInstance();
        DedaAuthRuntime.check();
        if (!await prefs.remove(verifiedUidKey)) {
          throw StateError('deda-stage2-pending-google-marker-not-cleared');
        }
        DedaAuthRuntime.check();
      },
    );
  }

  Future<DedaGoogleIdentityResult> signIn({
    required bool explicitAnonymousReplacement,
  }) async {
    if (!_enabled) throw StateError('deda-stable-google-feature-disabled');
    if (!DedaAuthRuntime.enabled ||
        _auth.app.name != FirebaseAuth.instance.app.name) {
      throw StateError('deda-google-requires-default-auth-guardian');
    }
    if (_busy) throw StateError('deda-google-login-already-in-progress');
    _busy = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final rememberedDedaLogin = prefs.getBool('deda_logged_in_v1') == true;
      final snapshot = DedaAuthRuntime.capture();
      final original = _auth.currentUser;
      final beforeUid = original?.uid;
      final admission = DedaStableGoogleLoginPolicy.admission(
        currentUid: beforeUid,
        currentIsAnonymous: original?.isAnonymous ?? false,
        hasVerifiedGoogleProvider: original?.providerData
              .any((provider) => provider.providerId == 'google.com') ?? false,
        explicitAnonymousReplacement: explicitAnonymousReplacement,
        hasRememberedDedaLogin: rememberedDedaLogin,
      );
      if (admission == DedaGoogleLoginAdmission.reuseExistingGoogle) {
        return DedaGoogleIdentityResult.verified(beforeUid!, reused: true);
      }
      if (admission == DedaGoogleLoginAdmission.explicitAnonymousReplacementRequired) {
        throw StateError('deda-google-explicit-anonymous-replacement-required');
      }
      if (admission == DedaGoogleLoginAdmission.explicitLocalDedaReplacementRequired) {
        throw StateError('deda-google-explicit-local-deda-replacement-required');
      }
      if (admission == DedaGoogleLoginAdmission.existingPasswordOrAdminSessionPreserved) {
        throw StateError('deda-google-preserve-existing-credential-session');
      }

      final oauth = await _credentialProvider.chooseCredential();
      if (oauth == null) return DedaGoogleIdentityResult.cancelled();
      // If another action changed the SDK principal during account selection,
      // NEVER allow this stale intent to overwrite it.
      if (_auth.currentUser?.uid != beforeUid) {
        throw StateError('deda-google-session-changed-during-selection');
      }
      if ((prefs.getBool('deda_logged_in_v1') == true) != rememberedDedaLogin) {
        throw StateError('deda-google-local-login-changed-during-selection');
      }
      // Google selection remains outside the lane: no network Auth mutation
      // occurs there. Recheck the epoch inside the existing shared lane.
      return await DedaAuthRuntime.run<DedaGoogleIdentityResult>(
        kind: DedaSessionTransitionKind.ownerLogin,
        origin: DedaSessionTransitionOrigin.userAction,
        verifiedOwnerLoginMaxWait: const Duration(seconds: 60),
        action: () async {
          DedaAuthRuntime.checkSnapshot(snapshot);
          DedaAuthRuntime.check();
          await prefs.reload();
          DedaAuthRuntime.check();
          if (_auth.currentUser?.uid != beforeUid ||
              (prefs.getBool('deda_logged_in_v1') == true) != rememberedDedaLogin) {
            throw StateError('deda-google-owner-intent-changed');
          }
          final credential = await DedaAuthRuntime.controller.transition<UserCredential>(
            kind: DedaSessionTransitionKind.ownerLogin,
            action: () => _auth.signInWithCredential(oauth),
            accepts: (result, live) => result.user != null &&
                result.user!.uid == live.uid &&
                live.kind == DedaSessionAuthKind.authenticated &&
                result.user!.providerData.any((p) => p.providerId == 'google.com'),
          );
          final current = _auth.currentUser;
          final uid = credential.user?.uid;
          if (uid == null || current == null ||
              !DedaStableGoogleLoginPolicy.isSameAuthenticatedGooglePrincipal(
                expectedUid: uid,
                actualUid: current.uid,
                actualIsAnonymous: current.isAnonymous,
                providerIds: current.providerData.map((p) => p.providerId),
              )) {
            throw StateError('deda-google-verified-principal-mismatch');
          }
          // Fence old local DEDA data; Google alone never grants ownership.
          DedaAuthRuntime.check();
          if (!await prefs.setBool('deda_logged_in_v1', false)) {
            throw StateError('deda-google-local-owner-fence-not-persisted');
          }
          DedaAuthRuntime.check();
          if (!await prefs.setString(verifiedUidKey, uid)) {
            throw StateError('deda-google-local-owner-fence-not-persisted');
          }
          DedaAuthRuntime.check();
          return DedaGoogleIdentityResult.verified(uid);
        },
      );
    } finally {
      _busy = false;
    }
  }
}
