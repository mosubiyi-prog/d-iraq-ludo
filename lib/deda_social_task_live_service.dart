import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

/// Client never writes private social configurations or reward balances.
/// Firebase Callable obtains trusted manager identity and server time.
class DedaLiveSocialTaskService {
  const DedaLiveSocialTaskService();

  Future<Map<String, dynamic>> command(Map<String, dynamic> data) async {
    final result = await FirebaseFunctions.instance
        .httpsCallable('dedaManageSocialTaskTrial')
        .call<Map<String, dynamic>>(data);
    return Map<String, dynamic>.from(result.data);
  }

  Future<Map<String, dynamic>> load() => command({'op': 'get'});

  Future<Map<String, dynamic>> save({
    required int expectedRevision,
    required String platform,
    required String action,
    required String title,
    required String url,
    required String unit,
    required int amount,
    required bool doubleWithAd,
    required String otherPlatform,
    required String otherAction,
  }) => command({
        'op': 'save',
        'expectedRevision': expectedRevision,
        'draft': {
          'platform': platform,
          'action': action,
          'title': title.trim(),
          'url': url.trim(),
          'rewardUnit': unit,
          'rewardAmount': amount,
          'doubleWithRewardedAd': doubleWithAd,
          'otherPlatform': otherPlatform.trim(),
          'otherAction': otherAction.trim(),
        },
      });

  Future<Map<String, dynamic>> schedule({
    required int expectedRevision,
    required String iraqDay,
  }) => command({
        'op': 'schedule', 'expectedRevision': expectedRevision,
        'day': iraqDay,
      });

  Future<Map<String, dynamic>> cancel({
    required int expectedRevision,
  }) => command({'op': 'cancel', 'expectedRevision': expectedRevision});

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchPublished() =>
      FirebaseFirestore.instance
          .collection('deda_social_task_public')
          .doc('featured')
          .snapshots();
}
