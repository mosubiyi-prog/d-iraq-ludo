import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'deda_qa32_premium_app_check.dart';
import 'deda_qa32_spark_public_identifier_directory.dart';

/// One read-only, trusted active-identifier -> immutable original-ID lookup.
/// Works for share-location recipients, add-friend search and other PUBLIC
/// canonical routing. Does not grant identifiers, spend gems, or change UID.
/// Gated until signed APK includes Firebase App Check + Functions deployment.
class DedaQa32PublicRecipientResolver {
  DedaQa32PublicRecipientResolver._();

  static const bool functionsEnabled = bool.fromEnvironment(
    'DEDA_PREMIUM_IDS_SERVER_LIVE', defaultValue: false,
  ) && bool.fromEnvironment(
    'DEDA_QA32_PUBLIC_RECIPIENT_LOOKUP_LIVE', defaultValue: false,
  );
  static const bool enabled =
      DedaQa32SparkPublicIdentifierDirectory.enabled || functionsEnabled;

  static final RegExp _requested = RegExp(r'^@DEDA-[A-Z0-9]{4,12}$');
  static final RegExp _original = RegExp(r'^@DEDA-[A-Z0-9]{6}$');

  /// The reply carries only three fields, NEVER UID/phone/accountKey/wallet.
  static String? canonicalFromVerifiedReply(
      Object? raw, String expectedSubmitted) {
    if (!_requested.hasMatch(expectedSubmitted) || raw is! Map) {
      throw StateError('public-id-unverified-input');
    }
    final row = Map<String, dynamic>.from(raw);
    if (row.length != 3 ||
        row['requestedId'] != expectedSubmitted ||
        row['serverConfirmed'] is! bool) {
      throw StateError('public-id-unverified-reply');
    }
    if (row['serverConfirmed'] == false) {
      if (row['originalId'] != null) {
        throw StateError('public-id-false-server-confirmation');
      }
      return null;
    }
    final result = row['originalId'];
    if (result is! String || !_original.hasMatch(result)) {
      throw StateError('public-id-original-invalid');
    }
    return result;
  }

  /// Caller MUST first check whether a 6-character ID is an existing
  /// canonical original, which takes precedence over a premium alias.
  static Future<String?> resolveActiveAlias(String raw) async {
    final requested = raw.trim().toUpperCase();
    if (!_requested.hasMatch(requested)) return null;
    if (!enabled || Firebase.apps.isEmpty) return null;
    if (DedaQa32SparkPublicIdentifierDirectory.enabled) {
      return DedaQa32SparkPublicIdentifierDirectory.resolveActiveAlias(
          requested);
    }
    final before = FirebaseAuth.instance.currentUser?.uid;
    if (before == null || before.isEmpty) return null;
    await DedaQa32PremiumAppCheck.ensureReady();
    final response = await FirebaseFunctions.instance
        .httpsCallable('dedaPremiumResolvePublicRecipient',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 30)))
        .call<Map<String, dynamic>>({'identifier': requested});
    if (FirebaseAuth.instance.currentUser?.uid != before) {
      throw StateError('public-id-requester-switched');
    }
    return canonicalFromVerifiedReply(response.data, requested);
  }
}
