import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'deda_backend.dart';

/// A question definition inside a manager-only, UNPUBLISHED survey draft.
/// This is configuration, NOT a user submission or proof of task completion.
class DedaSurveyQuestion {
  const DedaSurveyQuestion({
    required this.type,
    required this.promptAr,
    required this.promptEn,
    this.optionsAr = const <String>[],
    this.optionsEn = const <String>[],
    this.required = true,
  });

  final String type; // rating_5 | choice | text
  final String promptAr;
  final String promptEn;
  final List<String> optionsAr;
  final List<String> optionsEn;
  final bool required;

  void validate() {
    if (!{'rating_5', 'choice', 'text'}.contains(type)) {
      throw ArgumentError('unsupported-survey-question-type');
    }
    if (promptAr.trim().length < 3 || promptAr.trim().length > 160 ||
        promptEn.trim().length < 3 || promptEn.trim().length > 160) {
      throw ArgumentError('invalid-survey-question-prompt');
    }
    if (type == 'choice') {
      if (optionsAr.length < 2 || optionsAr.length > 5 ||
          optionsEn.length != optionsAr.length ||
          optionsAr.any((s) => s.trim().length < 1 || s.trim().length > 70) ||
          optionsEn.any((s) => s.trim().length < 1 || s.trim().length > 70)) {
        throw ArgumentError('invalid-survey-choice-options');
      }
    } else if (optionsAr.isNotEmpty || optionsEn.isNotEmpty) {
      throw ArgumentError('non-choice-options-not-allowed');
    }
  }

  Map<String, dynamic> toMap() {
    validate();
    return {
      'type': type,
      'promptAr': promptAr.trim(),
      'promptEn': promptEn.trim(),
      'optionsAr': optionsAr.map((e) => e.trim()).toList(growable: false),
      'optionsEn': optionsEn.map((e) => e.trim()).toList(growable: false),
      'required': required,
    };
  }

  factory DedaSurveyQuestion.fromMap(Map<String, dynamic> map) {
    return DedaSurveyQuestion(
      type: (map['type'] ?? '').toString(),
      promptAr: (map['promptAr'] ?? '').toString(),
      promptEn: (map['promptEn'] ?? '').toString(),
      optionsAr: (map['optionsAr'] is List)
          ? (map['optionsAr'] as List).map((e) => e.toString()).toList()
          : const [],
      optionsEn: (map['optionsEn'] is List)
          ? (map['optionsEn'] as List).map((e) => e.toString()).toList()
          : const [],
      required: map['required'] == true,
    );
  }
}

class DedaAdminSurveyDraft {
  const DedaAdminSurveyDraft({
    this.id = '',
    this.revision = 0,
    required this.titleAr,
    required this.titleEn,
    required this.questions,
    this.rewardUnit = 'none',
    this.rewardAmount = 0,
    this.durationDays = 14,
  });

  final String id;
  final int revision;
  final String titleAr;
  final String titleEn;
  final List<DedaSurveyQuestion> questions;
  final String rewardUnit; // none | coins | diamonds | legacy points (drafts only)
  final int rewardAmount;
  final int durationDays;

  void validate() {
    if (titleAr.trim().length < 3 || titleAr.trim().length > 80 ||
        titleEn.trim().length < 3 || titleEn.trim().length > 80) {
      throw ArgumentError('invalid-survey-title');
    }
    if (questions.isEmpty || questions.length > 6) {
      throw ArgumentError('invalid-survey-question-count');
    }
    for (final question in questions) {
      question.validate();
    }
    if (!{'none', 'coins', 'points', 'diamonds'}.contains(rewardUnit) ||
        rewardAmount < 0 ||
        rewardAmount > 1000000 ||
        (rewardUnit == 'none' && rewardAmount != 0) ||
        (rewardUnit != 'none' && rewardAmount == 0) ||
        durationDays < 1 ||
        durationDays > 90) {
      throw ArgumentError('invalid-survey-reward-or-duration');
    }
  }

  Map<String, dynamic> toEditableMap() {
    validate();
    return {
      'titleAr': titleAr.trim(),
      'titleEn': titleEn.trim(),
      'questions': questions.map((q) => q.toMap()).toList(growable: false),
      'rewardUnit': rewardUnit,
      'rewardAmount': rewardAmount,
      'durationDays': durationDays,
      // No user account can observe or claim any draft.
      'status': 'draft',
      // One future verified reward for the entire survey, never per question.
      // No draft can ever issue a balance credit or claim.
      // Only one verified claim per user/survey, irrespective of answer.
      'rewardPolicy': 'once_per_account_on_verified_submission',
    };
  }

  static DedaAdminSurveyDraft fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final raw = data['questions'];
    return DedaAdminSurveyDraft(
      id: document.id,
      revision: (data['revision'] as num?)?.toInt() ?? 0,
      titleAr: (data['titleAr'] ?? '').toString(),
      titleEn: (data['titleEn'] ?? '').toString(),
      questions: raw is List
          ? raw
              .whereType<Map>()
              .map((e) => DedaSurveyQuestion.fromMap(
                  Map<String, dynamic>.from(e)))
              .toList(growable: false)
          : const <DedaSurveyQuestion>[],
      rewardUnit: (data['rewardUnit'] ?? 'none').toString(),
      rewardAmount: (data['rewardAmount'] as num?)?.toInt() ?? 0,
      durationDays: (data['durationDays'] as num?)?.toInt() ?? 14,
    );
  }
}

/// UI access checks complement Firebase Security Rules; they do not replace
/// them. This service cannot publish, read submissions, or grant rewards.
class DedaAdminSurveyDraftService {
  const DedaAdminSurveyDraftService();

  CollectionReference<Map<String, dynamic>> get _collection =>
      FirebaseFirestore.instance.collection('admin_survey_drafts');

  Stream<List<DedaAdminSurveyDraft>> watchDrafts() {
    return _collection.snapshots().map((snapshot) {
      final drafts = snapshot.docs
          .map(DedaAdminSurveyDraft.fromDocument)
          .toList(growable: false);
      final sorted = List<DedaAdminSurveyDraft>.of(drafts)
        ..sort((a, b) => a.titleAr.compareTo(b.titleAr));
      return sorted;
    });
  }

  Future<String> save(DedaAdminSurveyDraft draft) async {
    final data = draft.toEditableMap();
    final profile = await DedaBackend.currentAdminProfile(forceRefresh: true);
    final user = FirebaseAuth.instance.currentUser;
    if (DedaBackend.normalizeAdminRole(profile['role']) != 'general_manager' ||
        user == null || user.isAnonymous || user.uid != profile['uid']) {
      throw StateError('general-manager-required');
    }

    final db = FirebaseFirestore.instance;
    final auditRef = db.collection('admin_audit').doc();
    final by = user.uid;
    final manager = (profile['displayName'] ?? '').toString();

    if (draft.id.isEmpty) {
      final ref = _collection.doc();
      final batch = db.batch();
      batch.set(ref, {
        ...data,
        'revision': 1,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'createdByUid': by,
        'updatedByUid': by,
      });
      batch.set(auditRef, {
        'action': 'admin_survey_draft_created',
        'adminUid': by,
        'adminName': manager,
        'adminRole': 'general_manager',
        'sourceCollection': 'admin_survey_drafts',
        'sourceId': ref.id,
        'questionCount': draft.questions.length,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
      return ref.id;
    }

    final ref = _collection.doc(draft.id);
    await db.runTransaction((tx) async {
      final snapshot = await tx.get(ref);
      final previous = snapshot.data();
      if (!snapshot.exists || previous == null) {
        throw StateError('survey-draft-not-found');
      }
      final revision = (previous['revision'] as num?)?.toInt() ?? 0;
      if (revision != draft.revision) {
        throw StateError('survey-draft-conflict');
      }
      if (previous['status'] != 'draft') {
        throw StateError('survey-draft-not-editable');
      }
      tx.update(ref, {
        ...data,
        'revision': revision + 1,
        'updatedByUid': by,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      tx.set(auditRef, {
        'action': 'admin_survey_draft_updated',
        'adminUid': by,
        'adminName': manager,
        'adminRole': 'general_manager',
        'sourceCollection': 'admin_survey_drafts',
        'sourceId': draft.id,
        'previousRevision': revision,
        'nextRevision': revision + 1,
        'questionCount': draft.questions.length,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
    return draft.id;
  }
}
