import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'deda_backend.dart';
import 'deda_qa32_premium_app_check.dart';

/// Owner QA only. Preserve canonical original account routing for ACTUAL
/// diamond transaction; display the active alias ONLY after verified server
/// lookup. Not enabled until backend/AppCheck/owner approval are in place.
class DedaQa32AdminGiftRecipientAliasBridge {
  static const bool enabled =
      bool.fromEnvironment('DEDA_PREMIUM_IDS_SERVER_LIVE', defaultValue: false) &&
      bool.fromEnvironment('DEDA_QA32_ADMIN_GIFT_RECIPIENT_ALIAS_LIVE',
          defaultValue: false);

  static final RegExp _identity = RegExp(r'^@DEDA-[A-Z0-9]{4,12}$');
  static final RegExp _original = RegExp(r'^@DEDA-[A-Z0-9]{6}$');

  /// Only three whitelisted public fields; caller-supplied original IDs,
  /// wallet balances or UIDs MUST NOT be trusted or mirrored into a gift.
  static String? verifiedOriginalFromReply(
      Object? value, String requestedIdentity) {
    if (!_identity.hasMatch(requestedIdentity) || value is! Map) {
      throw StateError('admin-gift-unverified-identity');
    }
    final row = Map<String, dynamic>.from(value);
    if (row.length != 3 || row['requestedId'] != requestedIdentity ||
        row['serverConfirmed'] is! bool) {
      throw StateError('admin-gift-malformed-server-proof');
    }
    if (row['serverConfirmed'] != true) {
      if (row['originalId'] != null) {
        throw StateError('admin-gift-false-positive-ownership');
      }
      return null;
    }
    final original = row['originalId'];
    if (original is! String || !_original.hasMatch(original)) {
      throw StateError('admin-gift-invalid-canonical-target');
    }
    return original;
  }

  static Future<Map<String, dynamic>?> verifiedTarget(String submittedId) async {
    final candidate = submittedId.trim().toUpperCase();
    if (!_identity.hasMatch(candidate)) return null;
    // Preserve the original, already proven gift recipient lookup forever.
    // Six-character premium IDs can also exist; only fall back when actual
    // personal original account wasn't found.
    if (_original.hasMatch(candidate)) {
      final original = await DedaBackend.adminDiamondGiftTarget(candidate);
      if (original != null) return original;
    }
    if (!enabled) return null;
    if (Firebase.apps.isEmpty) throw StateError('firebase-not-ready');
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('admin-authentication-required');
    }

    // Callable denies non-GM, missing AppCheck, forged or inactive alias,
    // and returns canonical original routing ID without private account data.
    await DedaQa32PremiumAppCheck.ensureReady();
    final response = await FirebaseFunctions.instance
        .httpsCallable('dedaPremiumResolveAdminGiftRecipient',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 30)))
        .call<Map<String, dynamic>>({'identifier': candidate});
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('admin-account-switched-during-lookup');
    }
    final canonical = verifiedOriginalFromReply(response.data, candidate);
    if (canonical == null) return null;
    final recipient = await DedaBackend.adminDiamondGiftTarget(canonical);
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('admin-account-switched-after-lookup');
    }
    if (recipient == null || recipient['publicId'] != canonical) {
      throw StateError('admin-recipient-original-owner-not-confirmed');
    }
    // Internal 'publicId' is STILL the immutable original ID used in
    // grantDiamondGift; the visual alias is read-only display metadata.
    return <String, dynamic>{
      ...recipient,
      'activeDisplayId': candidate,
      'verifiedCanonicalTarget': true,
    };
  }
}
