import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';

/// Stage-only client adapter. OFF by default until secure Cloud Functions
/// are deployed and signed off. Never attempts direct Firestore writes.
class DedaPlaceEngagementService {
  static const bool live = bool.fromEnvironment(
    'DEDA_PLACE_ENGAGEMENT_LIVE',
    defaultValue: false,
  );

  static Future<DedaPlaceEngagement> read(String placeId) async {
    if (!live || Firebase.apps.isEmpty || placeId.trim().isEmpty) {
      throw StateError('place-engagement-not-enabled');
    }
    final response = await FirebaseFunctions.instance
        .httpsCallable('dedaReadPlaceEngagement')
        .call(<String, Object>{'placeId': placeId});
    return DedaPlaceEngagement.fromMap(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  static Future<DedaPlaceEngagement> set({
    required String placeId,
    required String kind,
    required bool active,
  }) async {
    if (!live || Firebase.apps.isEmpty || placeId.trim().isEmpty) {
      throw StateError('place-engagement-not-enabled');
    }
    final response = await FirebaseFunctions.instance
        .httpsCallable('dedaSetPlaceEngagement')
        .call(<String, Object>{
          'placeId': placeId,
          'kind': kind,
          'active': active,
        });
    return DedaPlaceEngagement.fromMap(
      Map<String, dynamic>.from(response.data as Map),
    );
  }
}

class DedaPlaceEngagement {
  final bool following;
  final bool liked;
  final int followers;
  final int likes;

  const DedaPlaceEngagement({
    required this.following,
    required this.liked,
    required this.followers,
    this.likes = 0,
  });

  factory DedaPlaceEngagement.fromMap(Map<String, dynamic> map) {
    final count = (map['followers'] as num?)?.toInt() ?? 0;
    return DedaPlaceEngagement(
      following: map['following'] == true,
      liked: map['liked'] == true,
      followers: count < 0 ? 0 : count,
      likes: ((map['likes'] as num?)?.toInt() ?? 0).clamp(0, 1000000000).toInt(),
    );
  }
}
