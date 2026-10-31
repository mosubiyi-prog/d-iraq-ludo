import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'deda_admin_league_live_data.dart';
import 'deda_backend.dart';
import 'deda_weekly_league_clock.dart';

/// Manager ONLY: pauses *weekly leaderboard additions*, never the official
/// DEDA original level XP, daily task completion, friends or diamonds.
/// Immutable audit is written together with every state change.
class DedaAdminLeagueControls {
  DedaAdminLeagueControls({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;
  static final _id = RegExp(r'^@DEDA-[A-Z0-9]{4,12}$');
  static final _week = RegExp(r'^20[0-9]{2}-[0-9]{2}-[0-9]{2}$');

  DocumentReference<Map<String, dynamic>> get control =>
      _db.collection('deda_weekly_direct_control').doc('active');

  DocumentReference<Map<String, dynamic>> review(
          String weekId, String publicId) =>
      _db.collection('deda_weekly_direct_reviews')
          .doc(weekId).collection('users').doc(publicId);

  Future<String> _managerUid() async {
    final profile = await DedaBackend.currentAdminProfile(
      forceRefresh: true,
    );
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous ||
        DedaBackend.normalizeAdminRole(profile['role']) !=
            'general_manager' ||
        DedaBackend.normalizeAdminStatus(profile) != 'active') {
      throw StateError('active-general-manager-required');
    }
    return user.uid;
  }

  static String _reason(String input) {
    final reason = input.trim();
    if (reason.length < 8 || reason.length > 200 ||
        reason.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      throw ArgumentError('reason-must-be-8-to-200-characters');
    }
    return reason;
  }

  Future<void> setPaused({required bool paused,
      required String reason}) async {
    final who = await _managerUid();
    final why = _reason(reason);
    final id = DedaAdminLeagueLiveData.weekId(
        DedaWeeklyLeagueClock.at(DateTime.now().toUtc()).weekStart);
    final events = _db.collection('deda_weekly_direct_admin_events').doc();
    final batch = _db.batch();
    batch.set(control, {
      'paused': paused,
      'reason': why,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': who,
    });
    batch.set(events, {
      'action': paused ? 'pause' : 'resume',
      'weekId': id,
      'publicId': '',
      'reason': why,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': who,
    });
    await batch.commit();
  }

  Future<void> setFrozen({
    required String weekId,
    required String publicId,
    required bool frozen,
    required String reason,
  }) async {
    if (!_week.hasMatch(weekId) || !_id.hasMatch(publicId)) {
      throw ArgumentError('invalid weekly competitor identifier');
    }
    final who = await _managerUid();
    final why = _reason(reason);
    const frozenNotice =
        'تم تعليق اعتماد نقاطك في الدوري الأسبوعي مؤقتاً لغرض المراجعة. '
        'تستمر المهام ونقاط المستوى بصورة طبيعية.';
    const clearedNotice =
        'اكتملت مراجعة نقاط الدوري ورفعت الإدارة التجميد عن مشاركتك.';
    final doc = review(weekId, publicId);
    final noticeRef = _db.collection('deda_weekly_direct_notices')
        .doc(weekId).collection('users').doc(publicId);
    final events = _db.collection('deda_weekly_direct_admin_events').doc();
    final batch = _db.batch();
    batch.set(doc, <String, dynamic>{
      'weekId': weekId,
      'publicId': publicId,
      'frozen': frozen,
      'notice': frozen ? frozenNotice : clearedNotice,
      'reason': why,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': who,
    });
    // Privacy: notice is readable by the participant, administrative reason
    // stays only in the manager review document. Same atomic write batch.
    batch.set(noticeRef, <String, dynamic>{
      'weekId': weekId,
      'publicId': publicId,
      'frozen': frozen,
      'notice': frozen ? frozenNotice : clearedNotice,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': who,
    });
    batch.set(events, <String, dynamic>{
      'action': frozen ? 'freeze' : 'unfreeze',
      'weekId': weekId,
      'publicId': publicId,
      'reason': why,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': who,
    });
    await batch.commit();
  }
}
