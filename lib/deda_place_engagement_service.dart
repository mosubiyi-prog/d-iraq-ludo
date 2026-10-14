import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Stage-only client adapter. OFF by default until secure Cloud Functions
/// are deployed and signed off. Never attempts direct Firestore writes.
class DedaPlaceEngagementService {
  static const bool live = bool.fromEnvironment(
    'DEDA_PLACE_ENGAGEMENT_LIVE',
    defaultValue: false,
  );

  // Spark mode only works when a separately reviewed and published Firestore
  // ruleset enforces atomic totals. OFF by default. No account migration.
  static const bool sparkDirectLive = bool.fromEnvironment(
    'DEDA_SPARK_FIRESTORE_LIVE',
    defaultValue: false,
  );

  static Future<String> _verifiedAccountKey() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('verified-deda-account-required');
    }
    final db = FirebaseFirestore.instance;
    final session = await db.collection('deda_sessions').doc(uid).get();
    final user = await db.collection('users').doc(uid).get();
    final sessionKey = (session.data()?['accountKey'] ?? '').toString().trim();
    final userKey = (user.data()?['accountKey'] ?? '').toString().trim();
    if (sessionKey.isEmpty || sessionKey != userKey) {
      throw StateError('verified-deda-account-required');
    }
    // Existing DEDA accountKey gives one reaction per verified account even
    // after FirebaseAuth regenerates an anonymous uid on the same account.
    // Direct reads/listing of OTHER accounts' reaction rows are denied by rules.
    return sessionKey;
  }

  static Future<DedaPlaceEngagement> _sparkRead(String placeId) async {
    final accountKey = await _verifiedAccountKey();
    final db = FirebaseFirestore.instance;
    final totalsSnap = await db.collection('deda_spark_totals').doc(placeId).get();
    final reactionSnap = await db.collection('deda_spark_reactions')
        .doc(placeId).collection('users').doc(accountKey).get();
    final totals = totalsSnap.data() ?? const <String, dynamic>{};
    final row = reactionSnap.data() ?? const <String, dynamic>{};
    return DedaPlaceEngagement.fromMap(<String, dynamic>{
      'followers': totals['followers'] ?? 0,
      'likes': totals['likes'] ?? 0,
      'following': row['following'] == true,
      'liked': row['liked'] == true,
    });
  }

  static Future<DedaPlaceEngagement> _sparkSet({
    required String placeId,
    required String kind,
    required bool active,
  }) async {
    if (kind != 'follow' && kind != 'like') {
      throw ArgumentError.value(kind, 'kind');
    }
    final key = await _verifiedAccountKey();
    final db = FirebaseFirestore.instance;
    final totalsRef = db.collection('deda_spark_totals').doc(placeId);
    final reactionRef = db.collection('deda_spark_reactions').doc(placeId)
        .collection('users').doc(key);
    // Concurrent account actions can evaluate getAfter against a stale
    // aggregate before Firestore emits a retryable contention status.
    // Retry ONLY the entire transaction with new reads; never mutate user,
    // session or old totals, and never report success without server commit.
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        return await db.runTransaction<DedaPlaceEngagement>((tx) async {
      // Firestore requires every read before the first write.
      final totalsDoc = await tx.get(totalsRef);
      final rowDoc = await tx.get(reactionRef);
      final totalData = totalsDoc.data() ?? const <String, dynamic>{};
      final rowData = rowDoc.data() ?? const <String, dynamic>{};
      final following = rowData['following'] == true;
      final liked = rowData['liked'] == true;
      final followers = (totalData['followers'] as num?)?.toInt() ?? 0;
      final likes = (totalData['likes'] as num?)?.toInt() ?? 0;
      if (followers < 0 || likes < 0) {
        throw StateError('invalid-place-counter');
      }
      final current = kind == 'follow' ? following : liked;
      if (current == active) {
        return DedaPlaceEngagement(
          following: following, liked: liked,
          followers: followers, likes: likes,
        );
      }
      final nextFollowing = kind == 'follow' ? active : following;
      final nextLiked = kind == 'like' ? active : liked;
      final nextFollowers = followers +
          (kind == 'follow' ? (active ? 1 : -1) : 0);
      final nextLikes = likes +
          (kind == 'like' ? (active ? 1 : -1) : 0);
      if (nextFollowers < 0 || nextLikes < 0) {
        throw StateError('invalid-place-counter');
      }
      // Security rules validate BOTH documents' before/after states using
      // getAfter: an isolated counter or reaction write cannot be forged.
      tx.set(reactionRef, <String, bool>{
        'following': nextFollowing, 'liked': nextLiked,
      });
      tx.set(totalsRef, <String, int>{
        'followers': nextFollowers, 'likes': nextLikes,
      });
      return DedaPlaceEngagement(
        following: nextFollowing, liked: nextLiked,
        followers: nextFollowers, likes: nextLikes,
      );
        });
      } on FirebaseException catch (error) {
        if (error.code != 'permission-denied' || attempt == 3) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 60 * (attempt + 1)));
      }
    }
    throw StateError('unreachable-place-transaction');
  }

  static Future<DedaPlaceEngagement> read(String placeId) async {
    if (!live || Firebase.apps.isEmpty || placeId.trim().isEmpty) {
      throw StateError('place-engagement-not-enabled');
    }
    if (sparkDirectLive) return _sparkRead(placeId);
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
    if (sparkDirectLive) {
      return _sparkSet(placeId: placeId, kind: kind, active: active);
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
