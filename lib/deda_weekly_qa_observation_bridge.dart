import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Owner-approved QA observation ONLY. This is a client report of an already
/// locally rewarded original 100396 task; it is NOT proof that a task actually
/// happened and cannot be used for public rankings or real diamond payouts.
class DedaWeeklyQaObservationBridge {
  const DedaWeeklyQaObservationBridge._();

  static final RegExp _account = RegExp(r'^[0-9]{10,16}$');
  static const _tasks = <String>{
    'share_personal_location',
    'open_map',
    'share_registered_place',
    'open_saved_place',
    'open_received_place',
    'review_added_place',
    'traffic_skills',
    'long_trip',
  };

  static Future<bool> noteClaim({
    required String accountKey,
    required String taskId,
  }) async {
    if (!_account.hasMatch(accountKey) || !_tasks.contains(taskId)) {
      return false;
    }
    final before = FirebaseAuth.instance.currentUser;
    if (before == null || !before.isAnonymous) return false;
    final capturedUid = before.uid;
    try {
      final r = await FirebaseFunctions.instance.httpsCallable(
        'dedaWeeklyObserveTaskClaimQaV1',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 10)),
      ).call(<String, dynamic>{
        'accountKey': accountKey,
        'taskId': taskId,
      });
      if (FirebaseAuth.instance.currentUser?.uid != capturedUid) return false;
      final response = r.data;
      return response is Map &&
          (response['status'] == 'OBSERVATION_RECORDED_QA' ||
           response['status'] == 'OBSERVATION_ALREADY_RECORDED');
    } catch (_) {
      // Never roll back or modify a successfully claimed original 100396
      // level reward when the owner-only monitoring service is disabled.
      return false;
    }
  }

  static Future<int?> readOwnUnverifiedXp(String accountKey) async {
    if (!_account.hasMatch(accountKey)) return null;
    final before = FirebaseAuth.instance.currentUser;
    if (before == null || !before.isAnonymous) return null;
    try {
      final r = await FirebaseFunctions.instance.httpsCallable(
        'dedaWeeklyReadOwnObservationQaV1',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 10)),
      ).call(<String, dynamic>{'accountKey': accountKey});
      if (FirebaseAuth.instance.currentUser?.uid != before.uid) return null;
      final result = r.data;
      if (result is Map &&
          result['status'] == 'QA_OBSERVATION_ONLY_NOT_APPROVED' &&
          result['readOnly'] == true &&
          result['payoutEligible'] == false &&
          result['publicRankingAllowed'] == false &&
          result['independentlyVerified'] == false &&
          result['observedXp'] is int) {
        final points = result['observedXp'] as int;
        return points >= 0 && points <= 1120 && points % 20 == 0
            ? points : null;
      }
    } catch (_) {}
    return null;
  }
}
