import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Phase 2 is opt-in. The legacy published account and administrative login
/// remain untouched until full local DEDA enrollment and map/admin QA passes.
const bool dedaStableGoogleLoginEnabled = bool.fromEnvironment(
  'DEDA_STABILITY_GOOGLE_LOGIN', defaultValue: false,
);

enum DedaGoogleLoginAdmission {
  startFresh,
  reuseExistingGoogle,
  explicitAnonymousReplacementRequired,
  existingPasswordOrAdminSessionPreserved,
}

class DedaStableGoogleLoginPolicy {
  const DedaStableGoogleLoginPolicy._();

  static DedaGoogleLoginAdmission admission({
    required String? currentUid,
    required bool currentIsAnonymous,
    required bool hasVerifiedGoogleProvider,
    required bool explicitAnonymousReplacement,
  }) {
    if (currentUid == null || currentUid.trim().isEmpty) {
      return DedaGoogleLoginAdmission.startFresh;
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

  Future<DedaGoogleIdentityResult> signIn({
    required bool explicitAnonymousReplacement,
  }) async {
    if (!_enabled) throw StateError('deda-stable-google-feature-disabled');
    if (_busy) throw StateError('deda-google-login-already-in-progress');
    _busy = true;
    try {
      final original = _auth.currentUser;
      final beforeUid = original?.uid;
      final admission = DedaStableGoogleLoginPolicy.admission(
        currentUid: beforeUid,
        currentIsAnonymous: original?.isAnonymous ?? false,
        hasVerifiedGoogleProvider: original?.providerData
              .any((provider) => provider.providerId == 'google.com') ?? false,
        explicitAnonymousReplacement: explicitAnonymousReplacement,
      );
      if (admission == DedaGoogleLoginAdmission.reuseExistingGoogle) {
        return DedaGoogleIdentityResult.verified(beforeUid!, reused: true);
      }
      if (admission == DedaGoogleLoginAdmission.explicitAnonymousReplacementRequired) {
        throw StateError('deda-google-explicit-anonymous-replacement-required');
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
      final credential = await _auth.signInWithCredential(oauth);
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

      // A historical local phone/profile is NOT owned by this new Google UID.
      // Fence it off instead of projecting legacy ID, map, wallet, or role.
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setBool('deda_logged_in_v1', false) ||
          !await prefs.setString(verifiedUidKey, uid)) {
        throw StateError('deda-google-local-owner-fence-not-persisted');
      }
      return DedaGoogleIdentityResult.verified(uid);
    } finally {
      _busy = false;
    }
  }
}
