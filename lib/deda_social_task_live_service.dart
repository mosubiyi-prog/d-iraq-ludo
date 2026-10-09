import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Direct Firestore alternative for the Telegram-only first trial.
/// No Cloud Functions, scheduled backend job, wallet credit, or ad claim.
/// Security Rules check admin role, revisions, midnight, publication visibility.
/// Device time is used ONLY to choose the document ID; Firestore request.time
/// controls whether a future task is actually readable.
class DedaLiveSocialTaskService {
  const DedaLiveSocialTaskService();

  static const _draftPath = 'deda_social_direct_drafts';
  static const _daysPath = 'deda_social_direct_days';

  DocumentReference<Map<String, dynamic>> get _draft =>
      FirebaseFirestore.instance.collection(_draftPath).doc('featured');

  static String dayId(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  static DateTime get iraqNow =>
      DateTime.now().toUtc().add(const Duration(hours: 3));

  static DateTime midnightUtc(int year, int month, int day) =>
      DateTime.utc(year, month, day).subtract(const Duration(hours: 3));

  static bool allowedTelegramLink(String url) =>
      RegExp(r'^https://t\.me/[A-Za-z0-9_]{5,32}$').hasMatch(url);

  static String _managerUid() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      throw StateError('admin-session-required');
    }
    return user.uid;
  }

  Future<Map<String, dynamic>> load() async {
    _managerUid();
    final doc = await _draft.get(const GetOptions(source: Source.server));
    if (!doc.exists) return {'exists': false, 'revision': 0, 'status': 'new'};
    return {'exists': true, ...?doc.data()};
  }

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
  }) async {
    if (platform != 'telegram' || action != 'follow') {
      throw StateError('first-trial-telegram-follow-only');
    }
    if (title.trim().length < 3 || title.trim().length > 80 ||
        !allowedTelegramLink(url.trim()) || amount < 1 || amount > 5000 ||
        !{'points', 'coins', 'diamonds'}.contains(unit)) {
      throw StateError('invalid-telegram-task');
    }
    final uid = _managerUid();
    final db = FirebaseFirestore.instance;
    return db.runTransaction((tx) async {
      final oldDoc = await tx.get(_draft);
      final previous = oldDoc.data();
      final revision = (previous?['revision'] as num?)?.toInt() ?? 0;
      if (expectedRevision != revision) throw StateError('revision-conflict');
      final status = (previous?['status'] ?? 'new').toString();
      if (status == 'scheduled') {
        final at = previous?['activateAt'];
        if (at is! Timestamp || at.toDate().isAfter(DateTime.now().toUtc())) {
          throw StateError('cancel-future-schedule-first');
        }
      }
      final values = <String, dynamic>{
        'platform': 'telegram', 'action': 'follow',
        'title': title.trim(), 'url': url.trim(),
        'rewardUnit': unit, 'rewardAmount': amount,
        'doubleWithRewardedAd': doubleWithAd,
        'otherPlatform': '', 'otherAction': '',
        'status': 'draft', 'revision': revision + 1,
        'scheduledDay': '', 'activateAt': null,
        'rewardsEnabled': false,
        'updatedByUid': uid,
        'updatedAt': FieldValue.serverTimestamp(),
        if (!oldDoc.exists) ...{
          'createdByUid': uid,
          'createdAt': FieldValue.serverTimestamp(),
        },
      };
      if (oldDoc.exists) {
        tx.update(_draft, values);
      } else {
        tx.set(_draft, values);
      }
      return {...values, 'revision': revision + 1};
    });
  }

  Future<Map<String, dynamic>> schedule({
    required int expectedRevision,
    required String iraqDay,
  }) async {
    if (!RegExp(r'^20\d\d-\d\d-\d\d$').hasMatch(iraqDay)) {
      throw StateError('invalid-iraq-day');
    }
    final y = int.parse(iraqDay.substring(0, 4));
    final m = int.parse(iraqDay.substring(5, 7));
    final d = int.parse(iraqDay.substring(8, 10));
    final date = DateTime.utc(y, m, d);
    if (date.year != y || date.month != m || date.day != d ||
        iraqDay.compareTo(dayId(iraqNow)) <= 0) {
      throw StateError('next-day-required');
    }
    final at = Timestamp.fromDate(midnightUtc(y, m, d));
    final uid = _managerUid();
    final ref = FirebaseFirestore.instance.collection(_daysPath).doc(iraqDay);
    return FirebaseFirestore.instance.runTransaction((tx) async {
      final snapshots = await Future.wait([tx.get(_draft), tx.get(ref)]);
      final doc = snapshots[0];
      final old = doc.data();
      if (!doc.exists || old?['status'] != 'draft' ||
          (old?['revision'] as num?)?.toInt() != expectedRevision) {
        throw StateError('save-draft-first');
      }
      final prevDay = snapshots[1];
      if (prevDay.exists) throw StateError('day-already-scheduled');
      final values = <String, dynamic>{
        'dayId': iraqDay, 'year': y, 'month': m, 'day': d,
        'activateAt': at, 'status': 'scheduled',
        'revision': 1, 'platform': 'telegram', 'action': 'follow',
        'title': old!['title'], 'url': old['url'],
        'rewardUnit': old['rewardUnit'], 'rewardAmount': old['rewardAmount'],
        'doubleWithRewardedAd': old['doubleWithRewardedAd'],
        'rewardsEnabled': false,
        'rewardClaimMode': 'blocked-until-trusted-proof-and-ssv-ledger',
        'createdByUid': uid, 'updatedByUid': uid,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      tx.set(ref, values);
      tx.update(_draft, {
        'status': 'scheduled', 'revision': expectedRevision + 1,
        'scheduledDay': iraqDay, 'activateAt': at,
        'updatedByUid': uid, 'updatedAt': FieldValue.serverTimestamp(),
      });
      return {
        ...old, 'status': 'scheduled', 'revision': expectedRevision + 1,
        'scheduledDay': iraqDay, 'activateAt': at,
      };
    });
  }

  Future<Map<String, dynamic>> cancel({
    required int expectedRevision,
  }) async {
    final uid = _managerUid();
    return FirebaseFirestore.instance.runTransaction((tx) async {
      final control = await tx.get(_draft);
      final old = control.data();
      if (old?['status'] != 'scheduled' ||
          (old?['revision'] as num?)?.toInt() != expectedRevision) {
        throw StateError('no-cancellable-schedule');
      }
      final dayId = old!['scheduledDay'] as String;
      final dayRef = FirebaseFirestore.instance.collection(_daysPath).doc(dayId);
      final day = await tx.get(dayRef);
      if (!day.exists || day.data()?['status'] != 'scheduled') {
        throw StateError('scheduled-day-not-found');
      }
      tx.update(dayRef, {
        'status': 'cancelled',
        'revision': ((day.data()?['revision'] as num?)?.toInt() ?? 1) + 1,
        'updatedByUid': uid, 'updatedAt': FieldValue.serverTimestamp(),
      });
      tx.update(_draft, {
        'status': 'cancelled', 'revision': expectedRevision + 1,
        'updatedByUid': uid, 'updatedAt': FieldValue.serverTimestamp(),
      });
      return {...old, 'status': 'cancelled',
        'revision': expectedRevision + 1};
    });
  }

  /// Single server-only fetch, no Stream/cached future task leak.
  Future<Map<String, dynamic>?> publishedToday() async {
    final docId = dayId(iraqNow);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection(_daysPath).doc(docId)
          .get(const GetOptions(source: Source.server));
      final values = snapshot.data();
      final previewOnly = values != null &&
          values['rewardsEnabled'] == false &&
          values['rewardClaimMode'] ==
              'blocked-until-trusted-proof-and-ssv-ledger';
      final verifiedReward = values != null &&
          values['rewardsEnabled'] == true &&
          values['rewardClaimMode'] ==
              'server-verified-telegram-membership' &&
          values['platform'] == 'telegram' &&
          values['action'] == 'follow' &&
          values['rewardUnit'] == 'diamonds' &&
          values['rewardAmount'] == 10;
      if (!snapshot.exists || values == null ||
          values['status'] != 'scheduled' ||
          (!previewOnly && !verifiedReward)) {
        return null;
      }
      return values;
    } on FirebaseException catch (e) {
      // Before midnight, Firestore denies access to the future day's
      // document. Treat that as NO TASK; do not show cached content.
      if (e.code == 'permission-denied') return null;
      rethrow;
    }
  }
}
