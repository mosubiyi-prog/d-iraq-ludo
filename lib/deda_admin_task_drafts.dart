import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'deda_backend.dart';
import 'deda_daily_task_slots.dart';

/// Administrative task DRAFTS: not live task definitions or payout settings.
///
/// Existing user task points are currently awarded by a LOCAL task engine.
/// Never interpret an admin draft as authorization for giving points/gems.
/// Publication requires a separate, reviewed server-side reward ledger.
class DedaAdminTaskDraft {
  const DedaAdminTaskDraft({
    this.id = '',
    this.revision = 0,
    required this.cycle,
    required this.action,
    required this.titleAr,
    required this.titleEn,
    required this.targetCount,
    required this.rewardUnit,
    required this.rewardAmount,
    this.url = '',
  });

  final String id;
  final int revision;
  final String cycle;
  final String action;
  final String titleAr;
  final String titleEn;
  final int targetCount;
  final String rewardUnit;
  final int rewardAmount;
  final String url;

  static const Set<String> cycles = {'daily', 'weekly'};
  static const Set<String> actions = {
    'open_map',
    'share_personal_location',
    'share_registered_place',
    'open_saved_place',
    'open_received_place',
    'review_added_place',
    'traffic_skills',
    'long_trip',
    'visit_telegram',
  };
  static const Set<String> rewards = {'points', 'diamonds'};

  static String actionTitle(String action, bool arabic) {
    final titles = <String, (String, String)>{
      'open_map': ('فتح الخارطة', 'Open map'),
      'share_personal_location': ('مشاركة موقعك', 'Share your location'),
      'share_registered_place': ('مشاركة مكانك المسجل', 'Share registered place'),
      'open_saved_place': ('فتح مكان محفوظ', 'Open saved place'),
      'open_received_place': ('فتح موقع مستلم', 'Open received location'),
      'review_added_place': ('مراجعة مكانك', 'Review your place'),
      'traffic_skills': ('اختبار المهارات المرورية', 'Traffic skills quiz'),
      'long_trip': ('إتمام رحلة', 'Complete a trip'),
      'visit_telegram': ('زيارة قناة تليجرام', 'Visit Telegram channel'),
    };
    final pair = titles[action];
    return pair == null ? action : (arabic ? pair.$1 : pair.$2);
  }

  void validate() {
    if (!cycles.contains(cycle) || !actions.contains(action) ||
        !rewards.contains(rewardUnit)) {
      throw ArgumentError('unsupported-task-template');
    }
    if (titleAr.trim().length < 3 || titleAr.trim().length > 80 ||
        titleEn.trim().length < 3 || titleEn.trim().length > 80) {
      throw ArgumentError('invalid-task-title');
    }
    if (targetCount < 1 || targetCount > 100 ||
        rewardAmount < 1 || rewardAmount > 5000) {
      throw ArgumentError('invalid-task-limits');
    }
    if (action == 'visit_telegram') {
      final uri = Uri.tryParse(url.trim());
      if (uri == null || uri.scheme != 'https' ||
          !{'t.me', 'telegram.me'}.contains(uri.host.toLowerCase()) ||
          uri.pathSegments.where((s) => s.isNotEmpty).isEmpty ||
          uri.hasQuery || uri.hasFragment || uri.userInfo.isNotEmpty ||
          uri.port != 443) {
        throw ArgumentError('invalid-telegram-url');
      }
    } else if (url.trim().isNotEmpty) {
      throw ArgumentError('unexpected-task-url');
    }
  }

  Map<String, dynamic> toEditableMap() {
    validate();
    return {
      'cycle': cycle,
      'action': action,
      'titleAr': titleAr.trim(),
      'titleEn': titleEn.trim(),
      'targetCount': targetCount,
      'rewardUnit': rewardUnit,
      'rewardAmount': rewardAmount,
      'url': url.trim(),
      // Draft-only. No remote award/claim can be created by this page.
      'status': 'draft',
    };
  }

  static DedaAdminTaskDraft fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return DedaAdminTaskDraft(
      id: doc.id,
      revision: (data['revision'] as num?)?.toInt() ?? 0,
      cycle: (data['cycle'] ?? '').toString(),
      action: (data['action'] ?? '').toString(),
      titleAr: (data['titleAr'] ?? '').toString(),
      titleEn: (data['titleEn'] ?? '').toString(),
      targetCount: (data['targetCount'] as num?)?.toInt() ?? 1,
      rewardUnit: (data['rewardUnit'] ?? '').toString(),
      rewardAmount: (data['rewardAmount'] as num?)?.toInt() ?? 1,
      url: (data['url'] ?? '').toString(),
    );
  }
}

class DedaAdminTaskDraftService {
  const DedaAdminTaskDraftService();

  CollectionReference<Map<String, dynamic>> get _collection =>
      FirebaseFirestore.instance.collection('admin_task_drafts');

  Stream<List<DedaAdminTaskDraft>> watchDrafts() {
    // Firestore security rules require active general manager.
    return _collection.snapshots().map((snapshot) {
      final values = snapshot.docs.map(DedaAdminTaskDraft.fromDocument).toList();
      values.sort((a, b) => a.titleAr.compareTo(b.titleAr));
      return values;
    });
  }

  Future<String> save({
    required DedaAdminTaskDraft draft,
    String? dailySlotId,
  }) async {
    // A fixed slot is an admin-only draft overlay, never a live task.
    // Deliberately retain the legacy save() API for prior private drafts.
    final slot = dailySlotId == null ? null
        : DedaDailyTaskSlot.byId(dailySlotId);
    if (dailySlotId != null &&
        (slot == null || draft.cycle != 'daily' ||
         (draft.id.isNotEmpty && draft.id != slot.draftId))) {
      throw StateError('invalid-fixed-daily-slot');
    }
    final profile = await DedaBackend.currentAdminProfile(
      forceRefresh: true,
    );
    if (DedaBackend.normalizeAdminRole(profile['role']) !=
        'general_manager') {
      throw StateError('general-manager-required');
    }
    final current = FirebaseAuth.instance.currentUser;
    if (current == null || current.isAnonymous ||
        current.uid != profile['uid']) {
      throw StateError('admin-session-required');
    }

    final values = draft.toEditableMap();
    final actor = current.uid;
    final firestore = FirebaseFirestore.instance;
    final audit = firestore.collection('admin_audit').doc();

    if (draft.id.isEmpty) {
      final ref = slot == null ? _collection.doc() : _collection.doc(slot.draftId);
      final batch = firestore.batch();
      batch.set(ref, {
        ...values,
        'revision': 1,
        'createdByUid': actor,
        'updatedByUid': actor,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      batch.set(audit, {
        'action': 'task_draft_created',
        'adminUid': actor,
        'adminName': (profile['displayName'] ?? '').toString(),
        'adminRole': 'general_manager',
        'sourceCollection': 'admin_task_drafts',
        'sourceId': ref.id,
        'after': values,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
      return ref.id;
    }

    // Optimistic revision check prevents accidental overwrites if the draft
    // was changed by another general manager on another device.
    final ref = _collection.doc(draft.id);
    await firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists) throw StateError('task-draft-not-found');
      final previous = snapshot.data()!;
      final previousRevision =
          (previous['revision'] as num?)?.toInt() ?? 0;
      if (previousRevision != draft.revision) {
        throw StateError('task-draft-changed-remotely');
      }
      if (previous['status'] != 'draft') {
        throw StateError('only-draft-editing-allowed');
      }
      transaction.update(ref, {
        ...values,
        'revision': previousRevision + 1,
        'updatedByUid': actor,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(audit, {
        'action': 'task_draft_updated',
        'adminUid': actor,
        'adminName': (profile['displayName'] ?? '').toString(),
        'adminRole': 'general_manager',
        'sourceCollection': 'admin_task_drafts',
        'sourceId': draft.id,
        'before': {
          'titleAr': previous['titleAr'],
          'cycle': previous['cycle'],
          'action': previous['action'],
          'targetCount': previous['targetCount'],
          'rewardUnit': previous['rewardUnit'],
          'rewardAmount': previous['rewardAmount'],
        },
        'after': values,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
    return draft.id;
  }
}
