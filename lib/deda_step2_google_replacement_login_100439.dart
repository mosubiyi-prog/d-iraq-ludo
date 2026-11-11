import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'deda_100431_linked_owner_session_policy.dart';
import 'deda_auth_session_runtime.dart';
import 'deda_google_recovery_progress_100439.dart';
import 'deda_session_transition_gate.dart' show DedaSessionAuthKind;
import 'deda_step2_spark_linked_uid_readonly.dart';

/// ONLY for an explicitly approved private build. The signed 100439 APK,
/// existing PIN login, Firebase rules and financial records stay unchanged.
const bool dedaStep2GoogleReplacementLoginEnabled = bool.fromEnvironment(
  'DEDA_STEP2_GOOGLE_REPLACEMENT_LOGIN', defaultValue: false);

class DedaGoogleVerifiedExistingOwner {
  const DedaGoogleVerifiedExistingOwner({
    required this.originalUid,
    required this.accountKey,
    required this.originalId,
  });
  final String originalUid, accountKey, originalId;
}

/// Invariant: Google's identity alone does not prove a DEDA account.
/// Require an EXISTING Firebase IDP UID, then the same account's original
/// password provider, existing Firestore session and immutable ID route.
class DedaGoogleReplacementProof {
  const DedaGoogleReplacementProof._();

  // Auth Emulator demonstrated that the Identity Toolkit no-create REST
  // preflight can still create an Auth UID. A fresh Google principal must
  // NEVER be allowed to create an account while attempting legacy recovery.
  // This remains false until an approved non-creating server proof is
  // deployed and a signed-device test verifies its lifecycle.
  static const bool trustedReadOnlyProviderLookupDeployed = false;

  /// On a failed verification, clean up only the Google principal selected
  /// by THIS attempt. Another account may have signed in concurrently.
  static bool shouldSignOutFailedGoogleAttempt({
    required String? attemptedUid,
    required String? priorUid,
    required String? liveUid,
    required bool liveAnonymous,
  }) =>
      attemptedUid != null &&
      attemptedUid.isNotEmpty &&
      attemptedUid != priorUid &&
      liveUid == attemptedUid &&
      !liveAnonymous;

  static DedaGoogleVerifiedExistingOwner requireOriginalServerIdentity({
    required String expectedUid,
    required String currentUid,
    required String? currentEmail,
    required Iterable<({String providerId, String? email})> providers,
    required bool anonymous,
    required Map<String, dynamic>? user,
    required Map<String, dynamic>? directory,
    required Map<String, dynamic>? route,
    required Map<String, dynamic>? session,
    required bool adminDocumentExists,
  }) {
    final accountKey = user?['accountKey'];
    if (expectedUid.isEmpty || currentUid != expectedUid ||
        accountKey is! String ||
        !RegExp(r'^(?:07\d{9}|9647\d{9})$').hasMatch(accountKey)) {
      throw StateError('google-original-account-key-not-proven');
    }
    final providerRows = providers.toList(growable: false);
    // Insist on an already-linked Google + ORIGINAL password provider.
    // A fresh unrelated Google principal can never pass, even if its email
    // equals the typed owner's email.
    if (!providerRows.any((p) => p.providerId == 'google.com') ||
        !providerRows.any((p) =>
            p.providerId == 'password' &&
            DedaLinkedOwnerSessionPolicy.emailMatches(
                p.email, accountKey)) ||
        !DedaLinkedOwnerSessionPolicy.providerIdentityMatches(
          accountKey: accountKey, primaryEmail: currentEmail,
          providers: providerRows,
        )) {
      throw StateError('google-original-password-provider-not-linked');
    }
    final originalId = DedaStep2SparkLinkedUidReadOnlyProof.verify(
      accountKey: accountKey,
      originalUid: currentUid,
      authEmail: currentEmail,
      verifiedGoogleLinkedOriginal: true,
      anonymous: anonymous,
      directory: directory,
      user: user,
      route: route,
      session: session,
      adminDocumentExists: adminDocumentExists,
    );
    return DedaGoogleVerifiedExistingOwner(
      originalUid: currentUid, accountKey: accountKey, originalId: originalId);
  }
}

class DedaGoogleReplacementLogin {
  const DedaGoogleReplacementLogin._();

  // The former signInWithIdp(autoCreate:false) REST request was NOT
  // guaranteed non-creating in Firebase Auth Emulator. Removing the call
  // prevents accidental UID creation even if the private UI flag is enabled.
  // Future trusted server wiring must check a signed Google assertion and
  // an ALREADY linked provider without creating a Firebase Auth principal.
  static Future<String> _existingUid(String idToken) async {
    if (idToken.isEmpty) throw StateError('google-id-token-missing');
    throw StateError('google-read-only-provider-proof-not-deployed');
  }

  /// A successfully verified IDENTITY is not a restored profile or wallet.
  /// No DEDA profile preferences or database writes occur in this method.
  static Future<DedaGoogleVerifiedExistingOwner?> verifyOnNewPhone({
    required bool explicitUserAction,
    required bool Function() isCurrentIntent,
    DedaGoogleRecoveryProgress? onProgress,
  }) async {
    if (!explicitUserAction || !isCurrentIntent() ||
        !dedaStep2GoogleReplacementLoginEnabled ||
        !DedaGoogleReplacementProof.trustedReadOnlyProviderLookupDeployed ||
        !dedaLinkedOwnerCompatEnabled ||
        !dedaStep2SparkLinkedUidReadOnlyEnabled ||
        !DedaAuthRuntime.enabled || Firebase.apps.isEmpty) {
      throw StateError('google-replacement-login-not-approved');
    }
    final auth = FirebaseAuth.instance;
    final prior = auth.currentUser;
    if (prior != null && !prior.isAnonymous) {
      throw StateError('cannot-replace-existing-linked-or-admin-session');
    }
    // Collect the Google consent before acquiring the shared auth lane.
    final selected = await GoogleSignIn(scopes: <String>['email']).signIn();
    if (selected == null) return null;
    if (!isCurrentIntent() || auth.currentUser?.uid != prior?.uid) {
      throw StateError('google-owner-changed-after-account-choice');
    }
    onProgress?.call(DedaGoogleRecoveryStage.accountChosen);
    final tokens = await selected.authentication;
    final idToken = tokens.idToken;
    if (idToken == null || idToken.isEmpty ||
        !isCurrentIntent() || auth.currentUser?.uid != prior?.uid) {
      throw StateError('google-consent-or-existing-session-changed');
    }
    onProgress?.call(DedaGoogleRecoveryStage.googleTokenReceived);
    final existingUid = await _existingUid(idToken);
    if (!isCurrentIntent() || auth.currentUser?.uid != prior?.uid) {
      throw StateError('google-owner-intent-expired');
    }
    onProgress?.call(
        DedaGoogleRecoveryStage.existingGoogleProviderResolved);
    final credential = GoogleAuthProvider.credential(
        idToken: idToken, accessToken: tokens.accessToken);
    try {
      return await DedaAuthRuntime.run<DedaGoogleVerifiedExistingOwner>(
        kind: DedaSessionTransitionKind.ownerLogin,
        origin: DedaSessionTransitionOrigin.userAction,
        verifiedOwnerLoginMaxWait: const Duration(seconds: 90),
        isCurrent: isCurrentIntent,
        action: () async {
          if (auth.currentUser?.uid != prior?.uid ||
              (auth.currentUser != null &&
                  auth.currentUser?.isAnonymous != true)) {
            throw StateError('google-auth-principal-changed');
          }
          final result = await DedaAuthRuntime.controller
              .transition<UserCredential>(
            kind: DedaSessionTransitionKind.ownerLogin,
            action: () => auth.signInWithCredential(credential),
            accepts: (result, live) =>
                result.user?.uid == existingUid && live.uid == existingUid &&
                live.kind == DedaSessionAuthKind.authenticated,
          );
          final uid = result.user!.uid;
          onProgress?.call(DedaGoogleRecoveryStage.firebaseOriginalUidSignedIn);
          Future<Map<String, dynamic>?> server(String path) async {
            final row = await FirebaseFirestore.instance.doc(path).get(
                const GetOptions(source: Source.server));
            DedaAuthRuntime.check();
            if (row.metadata.isFromCache || row.metadata.hasPendingWrites ||
                auth.currentUser?.uid != uid) {
              throw StateError('google-original-owner-server-proof-failed');
            }
            return row.data();
          }
          final user = await server('users/$uid');
          final account = user?['accountKey'];
          if (account is! String ||
              !RegExp(r'^(?:07\d{9}|9647\d{9})$').hasMatch(account)) {
            throw StateError('google-uid-has-no-original-deda-account');
          }
          onProgress?.call(DedaGoogleRecoveryStage.originalUserReadFromServer);
          final originalId = user?['sharePersonalId'];
          if (originalId is! String ||
              !RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(originalId)) {
            throw StateError('google-original-share-id-not-proven');
          }
          final rows = await Future.wait([
            server('deda_account_directory/$account'),
            server('deda_sessions/$uid'),
            server('deda_share_ids/$originalId'),
            server('admins/$uid'),
          ]);
          onProgress?.call(DedaGoogleRecoveryStage.ownerDocumentsReadFromServer);
          final confirmed = DedaGoogleReplacementProof
              .requireOriginalServerIdentity(
            expectedUid: existingUid, currentUid: uid,
            currentEmail: auth.currentUser?.email,
            providers: auth.currentUser!.providerData.map((p) =>
                (providerId: p.providerId, email: p.email)),
            anonymous: auth.currentUser!.isAnonymous,
            user: user, directory: rows[0], session: rows[1],
            route: rows[2], adminDocumentExists: rows[3] != null,
          );
          if (!isCurrentIntent() || auth.currentUser?.uid != existingUid) {
            throw StateError('google-original-owner-changed-after-readback');
          }
          onProgress?.call(DedaGoogleRecoveryStage.originalOwnerVerified);
          // This is NOT guardian restoration or a verified diamond receipt.
          return confirmed;
        },
      );
    } catch (_) {
      // A failed proof must not leave this attempted principal as DEDA's
      // owner. Never sign out an unrelated account that changed in flight.
      // Never delete/merge an Auth account or modify a user's data.
      final current = auth.currentUser;
      if (DedaGoogleReplacementProof.shouldSignOutFailedGoogleAttempt(
          attemptedUid: existingUid, priorUid: prior?.uid,
          liveUid: current?.uid,
          liveAnonymous: current?.isAnonymous ?? true)) {
        // Firebase Auth has no atomic conditional sign-out. Recheck now.
        if (auth.currentUser?.uid == existingUid) {
          try { await auth.signOut(); } catch (_) { /* Never expose token. */ }
        }
      }
      rethrow;
    }
  }
}
