import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Real shared account/week scores from server. Never send XP amount, wallet,
/// displayed ID, or rank from phone. Backend always computes +20 once/day/task.
/// Original XP reward in 100396 remains untouched.
class DedaWeeklyOwnerPilotBridge {
  const DedaWeeklyOwnerPilotBridge._();

  static const _tasks = <String>{
    'share_personal_location', 'open_map', 'share_registered_place',
    'open_saved_place', 'open_received_place', 'review_added_place',
    'traffic_skills', 'long_trip',
  };

  static Future<bool> claimAfterOriginalReward({
    required String accountKey,
    required String taskId,
  }) async {
    if (!_tasks.contains(taskId) ||
        !RegExp(r'^[0-9]{10,16}$').hasMatch(accountKey)) return false;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !user.isAnonymous) return false;
    final uid = user.uid;
    try {
      final result = await FirebaseFunctions.instance.httpsCallable(
        'dedaWeeklyOwnerPilotClaimV1',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 12)),
      ).call(<String, dynamic>{'accountKey': accountKey,'taskId': taskId});
      if (FirebaseAuth.instance.currentUser?.uid != uid) return false;
      final data = result.data;
      return data is Map &&
          (data['status'] == 'COUNTED_OWNER_QA' ||
           data['status'] == 'ALREADY_RECORDED');
    } catch (_) {
      // Never change or revoke original XP/diamonds on a network failure.
      return false;
    }
  }

  static Future<Object?> loadStandings({
    required String accountKey,
    required bool Function() sameViewer,
  }) async {
    if (!sameViewer() ||
        !RegExp(r'^[0-9]{10,16}$').hasMatch(accountKey)) {
      throw StateError('deda-weekly-account-not-ready');
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !user.isAnonymous) {
      throw StateError('deda-weekly-auth-required');
    }
    final uid = user.uid;
    final result = await FirebaseFunctions.instance.httpsCallable(
      'dedaWeeklyOwnerPilotStandingsV1',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 12)),
    ).call(<String, dynamic>{'accountKey':accountKey});
    if (!sameViewer() || FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('deda-weekly-account-switched');
    }
    return result.data;
  }
}
