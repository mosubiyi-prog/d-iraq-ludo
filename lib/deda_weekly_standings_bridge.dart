import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// VERIFIED-only standings transport for DEDA 100396.
/// Task XP is never sent from the phone. No local scores are trusted.
class DedaWeeklyStandingsBridge {
  const DedaWeeklyStandingsBridge._();

  static Future<Object?> load({
    required String accountKey,
    required bool Function() currentAccountStillAuthorized,
  }) async {
    if (!currentAccountStillAuthorized() ||
        !RegExp(r'^[0-9]{10,16}$').hasMatch(accountKey)) {
      throw StateError('deda-weekly-account-changed');
    }
    final before = FirebaseAuth.instance.currentUser;
    if (before == null || !before.isAnonymous) {
      throw StateError('deda-weekly-auth-required');
    }
    final uid = before.uid;
    final result = await FirebaseFunctions.instance.httpsCallable(
      'dedaWeeklyVerifiedStandingsV1',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 12)),
    ).call(<String,dynamic>{'accountKey':accountKey});
    if (!currentAccountStillAuthorized() ||
        FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('deda-weekly-stale-account-response');
    }
    // The existing DedaWeeklyServerSnapshotPair validates both weeks,
    // all 10 rank slots, identities and prize display values.
    return result.data;
  }
}
