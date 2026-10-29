import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Official DEDA weekly-leaderboard transport. Scores, ranks and awards NEVER
/// come from local SharedPreferences or a client Firestore query.
///
/// The matching production callable is intentionally not deployed. Until a
/// server-issued verified CURRENT and PREVIOUS snapshot exists, this throws;
/// the guarded leaderboard screen shows an unverified/pending state instead
/// of fabricating a rank or changing the user's points/diamonds.
class DedaWeeklyVerifiedStandingsBridge {
  const DedaWeeklyVerifiedStandingsBridge._();

  static Future<Object?> load({
    required String accountKey,
    required bool Function() currentAccountStillAuthorized,
  }) async {
    if (!currentAccountStillAuthorized() ||
        !RegExp(r'^[0-9]{8,15}$').hasMatch(accountKey)) {
      throw StateError('deda-weekly-session-changed');
    }
    final user = FirebaseAuth.instance.currentUser;
    final capturedUid = user?.uid;
    if (capturedUid == null || user?.isAnonymous != true) {
      throw StateError('deda-weekly-auth-required');
    }
    final callable = FirebaseFunctions.instance.httpsCallable(
      'dedaWeeklyVerifiedStandingsV1',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 12)),
    );
    final response = await callable.call(<String, dynamic>{
      'accountKey': accountKey,
    });
    if (!currentAccountStillAuthorized() ||
        FirebaseAuth.instance.currentUser?.uid != capturedUid) {
      throw StateError('deda-weekly-stale-response');
    }
    // The guarded screen independently rejects unsigned/malformed standings.
    return response.data;
  }
}
