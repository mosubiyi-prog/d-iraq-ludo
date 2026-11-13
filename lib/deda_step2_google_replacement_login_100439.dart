import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
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

/// Token for the exact previously-linked Firebase UID. Never accept a
/// client-chosen UID; cross-check against no-create Identity Toolkit proof.
class DedaGoogleExistingUidServerTicket {
  const DedaGoogleExistingUidServerTicket({
    required this.originalUid, required this.customToken,
  });
  final String originalUid, customToken;
  factory DedaGoogleExistingUidServerTicket.fromCallable(Object? raw, {
    required String expectedExistingUid,
  }) {
    if (raw is! Map) throw StateError('google-existing-uid-server-denied');
    final uid = raw['originalUid'], token = raw['customToken'];
    if (uid is! String || !RegExp(r'^[A-Za-z0-9:_-]{6,128}$').hasMatch(uid) ||
        uid != expectedExistingUid || token is! String ||
        token.isEmpty || token.length > 8192) {
      throw StateError('google-existing-uid-server-mismatch');
    }
    return DedaGoogleExistingUidServerTicket(
        originalUid: uid, customToken: token);
  }
}

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

  static Map<String, Object> existingIdpRequest(String idToken) {
    if (idToken.isEmpty) throw StateError('google-id-token-missing');
    return <String, Object>{
      'requestUri': 'http://localhost',
      'postBody': Uri(queryParameters: <String, String>{
        'id_token': idToken,
        'providerId': 'google.com',
      }).query,
      'returnSecureToken': true,
      'autoCreate': false,
    };
  }

  static String existingUidOnly(Map<String, dynamic> response) {
    final value = response['localId'];
    // A missing isNewUser verdict is NOT evidence of an existing
    // Google-linked Firebase principal. Deny rather than risk a new UID.
    if (value is! String || value.length < 6 ||
        response['isNewUser'] != false ||
        response['needConfirmation'] == true) {
      throw StateError('google-provider-does-not-resolve-existing-uid');
    }
    return value;
  }

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

  /// This preliminary Identity Toolkit request is deliberately no-create.
  /// Do not invoke FirebaseAuth.signInWithCredential() without obtaining
  /// the UID of an ALREADY linked Google provider in this same project.
  /// REST failures (including disabled/enumeration-protected provider or
  /// unsupported no-create mode) must deny login; never fall back to create.
  static Future<String> _existingUid(String idToken) async {
    final apiKey = Firebase.app().options.apiKey;
    if (apiKey.isEmpty) throw StateError('firebase-project-not-configured');
    final uri = Uri.https('identitytoolkit.googleapis.com',
        '/v1/accounts:signInWithIdp', <String, String>{'key': apiKey});
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.postUrl(uri).timeout(
          const Duration(seconds: 8));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(
          DedaGoogleReplacementProof.existingIdpRequest(idToken)));
      final response = await request.close().timeout(
          const Duration(seconds: 10));
      final body = await utf8.decoder.bind(response).join().timeout(
          const Duration(seconds: 10));
      if (response.statusCode != HttpStatus.ok) {
        throw StateError('google-existing-provider-preflight-denied');
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw StateError('google-existing-provider-malformed');
      }
      return DedaGoogleReplacementProof.existingUidOnly(decoded);
    } finally {
      client.close(force: true);
    }
  }

  /// A successfully verified IDENTITY is not a restored profile or wallet.
  /// No DEDA profile preferences or database writes occur in this method.
  /// Trusted callable: signed Google subject + provider + original UID,
  /// verified by AppCheck and canonical account documents before token issue.
  /// A missing or unapproved endpoint must fail without Firebase SDK sign-in.
  static Future<DedaGoogleExistingUidServerTicket> _serverTicket(
      String idToken, String expectedUid) async {
    final callable = FirebaseFunctions.instance.httpsCallable(
      'dedaGoogleExistingUidTokenV1',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
    );
    final response = await callable.call(<String, Object>{
      'googleIdToken': idToken,
    });
    return DedaGoogleExistingUidServerTicket.fromCallable(
      response.data, expectedExistingUid: expectedUid);
  }

  static Future<DedaGoogleVerifiedExistingOwner?> verifyOnNewPhone({
    required bool explicitUserAction,
    required bool Function() isCurrentIntent,
    DedaGoogleRecoveryProgress? onProgress,
  }) async {
    if (!explicitUserAction || !isCurrentIntent() ||
        !dedaStep2GoogleReplacementLoginEnabled ||
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
    // signInWithCredential can CREATE an unrelated UID on a provider race.
    // Server issues a custom token strictly for the pre-existing original UID.
    final ticket = await _serverTicket(idToken, existingUid);
    if (!isCurrentIntent() || auth.currentUser?.uid != prior?.uid ||
        ticket.originalUid != existingUid) {
      throw StateError('google-existing-owner-ticket-expired');
    }
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
            action: () => auth.signInWithCustomToken(ticket.customToken),
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
      // A failed identity proof must not leave a wrong login visible in DEDA.
      // Never delete or merge a Firebase Auth account or touch user data.
      final current = auth.currentUser;
      if (current != null && !current.isAnonymous &&
          current.uid != prior?.uid) {
        try { await auth.signOut(); } catch (_) { /* Never expose token. */ }
      }
      rethrow;
    }
  }
}
