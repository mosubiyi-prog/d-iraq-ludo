import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'deda_admin_task_drafts.dart';
import 'deda_backend.dart';
import 'deda_daily_schedule_policy.dart';
import 'deda_daily_task_slots.dart';

/// A private, never-published manager preview. This record must NEVER be
/// consumed by the ordinary user's task engine or by the reward ledger.
class DedaDailySchedulePreview {
  const DedaDailySchedulePreview({
    required this.slotId,
    required this.status,
    required this.revision,
    required this.effectiveAt,
    required this.titleAr,
  });

  final String slotId;
  final String status;
  final int revision;
  final DateTime effectiveAt;
  final String titleAr;

  bool canCancel(DateTime now) => DedaDailySchedulePolicy.canCancel(
        status: status,
        effectiveAt: effectiveAt,
        trustedNow: now,
      );

  static DedaDailySchedulePreview fromDocument(
      QueryDocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data();
    final date = data['effectiveAt'];
    return DedaDailySchedulePreview(
      slotId: (data['slotId'] ?? '').toString(),
      status: (data['status'] ?? '').toString(),
      revision: (data['revision'] as num?)?.toInt() ?? 0,
      effectiveAt:
          date is Timestamp ? date.toDate().toUtc() : DateTime.utc(1970),
      titleAr: (data['titleAr'] ?? '').toString(),
    );
  }
}

/// Manager-only preview storage using an immutable slot document ID.
/// A separate approved backend must later implement actual publication.
class DedaDailySchedulePreviewService {
  const DedaDailySchedulePreviewService();

  CollectionReference<Map<String, dynamic>> get _previews =>
      FirebaseFirestore.instance.collection('admin_daily_schedule_previews');

  Stream<List<DedaDailySchedulePreview>> watchPreviews() =>
      _previews.snapshots().map((snapshot) => snapshot.docs
          .map(DedaDailySchedulePreview.fromDocument)
          .toList(growable: false));

  Future<({String uid, String name})> _requireManager() async {
    final profile = await DedaBackend.currentAdminProfile(forceRefresh: true);
    final current = FirebaseAuth.instance.currentUser;
    if (current == null ||
        current.isAnonymous ||
        DedaBackend.normalizeAdminRole(profile['role']) != 'general_manager' ||
        profile['uid'] != current.uid) {
      throw StateError('general-manager-required');
    }
    return (
      uid: current.uid,
      name: (profile['displayName'] ?? '').toString(),
    );
  }

  Future<void> prepare({
    required DedaDailyTaskSlot slot,
    required DedaAdminTaskDraft draft,
  }) async {
    if (draft.cycle != 'daily') throw ArgumentError('Only daily previews');
    draft.validate();
    final actor = await _requireManager();
    final now = DateTime.now();
    final next = DedaDailySchedulePolicy.nextActivationUtc(now);
    DedaDailySchedulePolicy.validatePreview(
      slotId: slot.id,
      status: DedaDailySchedulePolicy.pending,
      effectiveAt: next,
      trustedNow: now,
    );

    final db = FirebaseFirestore.instance;
    final reference = _previews.doc(DedaDailySchedulePolicy.previewId(slot.id));
    final audit = db.collection('admin_audit').doc();
    final values = draft.toEditableMap();
    await db.runTransaction((tx) async {
      final snapshot = await tx.get(reference);
      final previous = snapshot.data();
      final revision = (previous?['revision'] as num?)?.toInt() ?? 0;
      final map = <String, dynamic>{
        'slotId': slot.id,
        'action': draft.action,
        'titleAr': draft.titleAr.trim(),
        'titleEn': draft.titleAr.trim(),
        'targetCount': draft.targetCount,
        'rewardUnit': draft.rewardUnit,
        'rewardAmount': draft.rewardAmount,
        'url': draft.url.trim(),
        'status': DedaDailySchedulePolicy.pending,
        'revision': revision + 1,
        'effectiveAt': Timestamp.fromDate(next),
        'updatedByUid': actor.uid,
        'updatedAt': FieldValue.serverTimestamp(),
        if (!snapshot.exists) ...{
          'createdByUid': actor.uid,
          'createdAt': FieldValue.serverTimestamp(),
        },
      };
      if (snapshot.exists) {
        tx.update(reference, map);
      } else {
        tx.set(reference, map);
      }
      tx.set(audit, {
        'action': 'daily_schedule_preview_prepared',
        'adminUid': actor.uid,
        'adminName': actor.name,
        'adminRole': 'general_manager',
        'sourceCollection': 'admin_daily_schedule_previews',
        'sourceId': reference.id,
        'slotId': slot.id,
        'revision': revision + 1,
        'after': values,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> cancel(String slotId) async {
    final actor = await _requireManager();
    final id = DedaDailySchedulePolicy.previewId(slotId);
    final db = FirebaseFirestore.instance;
    final reference = _previews.doc(id);
    final audit = db.collection('admin_audit').doc();

    await db.runTransaction((tx) async {
      final snapshot = await tx.get(reference);
      final previous = snapshot.data();
      if (!snapshot.exists || previous == null) {
        throw StateError('scheduled-preview-not-found');
      }
      final timestamp = previous['effectiveAt'];
      if (timestamp is! Timestamp ||
          !DedaDailySchedulePolicy.canCancel(
            status: (previous['status'] ?? '').toString(),
            effectiveAt: timestamp.toDate(),
            trustedNow: DateTime.now(),
          )) {
        throw StateError('scheduled-preview-no-longer-cancellable');
      }
      final revision = (previous['revision'] as num?)?.toInt() ?? 0;
      tx.update(reference, {
        'status': DedaDailySchedulePolicy.cancelled,
        'revision': revision + 1,
        'updatedByUid': actor.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      tx.set(audit, {
        'action': 'daily_schedule_preview_cancelled',
        'adminUid': actor.uid,
        'adminName': actor.name,
        'adminRole': 'general_manager',
        'sourceCollection': 'admin_daily_schedule_previews',
        'sourceId': id,
        'slotId': slotId,
        'revision': revision + 1,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
