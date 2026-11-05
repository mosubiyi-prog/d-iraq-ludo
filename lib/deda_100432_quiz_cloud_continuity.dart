import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'deda_100429_local_task_traffic_evidence.dart';
import 'deda_100430_quiz_ui_hydration.dart';
import 'deda_100431_linked_owner_session_policy.dart';

/// DEDA step 2: server-backed account QUIZ UI continuity without balances,
/// spending, rewards or any new device-authority over the original ID.
///
/// NOT ACTIVE IN USERS' APKS. Explicitly requires a separate owner-approved
/// Firestore Rules release and stronger authenticated account-owner flow.
/// Firestore holds only self-authored/untrusted quiz display state.
const dedaQuizCloudSyncEnabled = bool.fromEnvironment(
  'DEDA_STEP2_QUIZ_CLOUD', defaultValue: false);

abstract class DedaQuizCloudTransport {
  Future<Map<String, dynamic>?> read({
    required String uid, required String day,
  });
  /// Must create once using a transaction and reject changed payload
  /// for the same immutable user/date document.
  Future<void> createOnce({
    required String uid, required String day,
    required Map<String, dynamic> fields,
  });
}

class DedaFirestoreQuizCloudTransport implements DedaQuizCloudTransport {
  const DedaFirestoreQuizCloudTransport();

  DocumentReference<Map<String, dynamic>> _ref(String uid, String day) =>
      FirebaseFirestore.instance.collection('deda_quiz_ui_snapshots')
          .doc(uid).collection('days').doc(day);

  @override
  Future<Map<String, dynamic>?> read({
    required String uid, required String day,
  }) async {
    final snap = await _ref(uid, day).get(
      const GetOptions(source: Source.server));
    return snap.data();
  }

  @override
  Future<void> createOnce({
    required String uid, required String day,
    required Map<String, dynamic> fields,
  }) async {
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final ref = _ref(uid, day);
      final before = await tx.get(ref);
      if (before.exists) {
        final data = before.data() ?? <String, dynamic>{};
        if (data['encoded'] != fields['encoded'] ||
            data['uid'] != uid || data['day'] != day ||
            data['originalId'] != fields['originalId'] ||
            data['accountKey'] != fields['accountKey'] ||
            data['kind'] != fields['kind']) {
          throw StateError('old-phone-quiz-backup-conflict');
        }
        return;
      }
      tx.set(ref, <String, dynamic>{
        ...fields,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }
}

class DedaQuizCloudContinuity {
  const DedaQuizCloudContinuity({
    required this.transport,
    required this.currentUid,
    required this.verifyLinkedOwner,
    required this.uiHydration,
    this.enabled = dedaQuizCloudSyncEnabled,
  });

  factory DedaQuizCloudContinuity.firebase() => DedaQuizCloudContinuity(
    transport: const DedaFirestoreQuizCloudTransport(),
    currentUid: () => FirebaseAuth.instance.currentUser?.uid,
    verifyLinkedOwner: (uid, accountKey) async {
      final user = FirebaseAuth.instance.currentUser;
      return user?.uid == uid &&
          await DedaLinkedOwnerSessionPolicy.verified(user, accountKey);
    },
    uiHydration: const DedaQuizUiHydration(
      DedaSharedPreferencesQuizUiRestoreStore()),
  );

  final bool enabled;
  final DedaQuizCloudTransport transport;
  final String? Function() currentUid;
  final Future<bool> Function(String uid, String accountKey) verifyLinkedOwner;
  final DedaQuizUiHydration uiHydration;

  void _check(String uid, bool Function() current) {
    if (!enabled || !current() || uid.isEmpty || currentUid() != uid) {
      throw StateError('quiz-cloud-account-changed-or-disabled');
    }
  }

  Future<void> _owner(String uid, String accountKey,
      bool Function() isCurrent) async {
    _check(uid, isCurrent);
    if (!await verifyLinkedOwner(uid, accountKey)) {
      throw StateError('quiz-cloud-original-owner-not-proven');
    }
    _check(uid, isCurrent);
  }

  DedaStep2UiCapture _quizOnly(DedaStep2UiCapture input) {
    DedaQuizUiHydration.validateUiOnly(input);
    // NEVER upload taskPointsRaw. It contains old local task awards which
    // are not server-verified and could otherwise become fake receipts.
    final filtered = Map<String, Object?>.from(input.toJson())
      ..['taskPointsRaw'] = null;
    return DedaStep2UiCapture.decodeForAccount(jsonEncode(filtered),
      accountKey: input.accountKey,
      originalId: input.originalId,
      iraqDay: input.iraqDay);
  }

  Map<String, dynamic> _fields(DedaStep2UiCapture safe, String uid) =>
      <String, dynamic>{
        'format': 1,
        'kind': 'display-only-untrusted-quiz-v1',
        'uid': uid,
        'accountKey': safe.accountKey,
        'originalId': safe.originalId,
        'day': safe.iraqDay,
        'encoded': safe.encode(),
      };

  /// Old phone: one immutable quiz-only snapshot after same-UID owner proof.
  /// Does not grant points or override any financial/event ledger.
  Future<void> saveOldPhoneQuiz({
    required String uid,
    required DedaStep2UiCapture source,
    required bool Function() isCurrent,
  }) async {
    await _owner(uid, source.accountKey, isCurrent);
    final safe = _quizOnly(source);
    if (safe.encode().length > 60000) {
      throw StateError('quiz-cloud-payload-too-large');
    }
    final fields = _fields(safe, uid);
    _check(uid, isCurrent);
    await transport.createOnce(
      uid: uid, day: safe.iraqDay, fields: fields);
    await _owner(uid, source.accountKey, isCurrent);
    final verified = await transport.read(uid:uid,day:safe.iraqDay);
    if (verified == null ||
        verified['encoded'] != fields['encoded'] ||
        verified['accountKey'] != source.accountKey ||
        verified['originalId'] != source.originalId ||
        verified['uid'] != uid) {
      throw StateError('quiz-cloud-write-readback-not-confirmed');
    }
    _check(uid, isCurrent);
  }

  /// Replacement phone: only missing quiz UI keys. Repeated call is a
  /// no-op; existing other-device quiz data never overwritten.
  /// Does not touch task_points, total XP, diamonds, rank or claim receipts.
  Future<bool> restoreNewPhoneQuiz({
    required String uid,
    required String accountKey,
    required String originalId,
    required String iraqDay,
    required bool Function() isCurrent,
  }) async {
    await _owner(uid, accountKey, isCurrent);
    final record = await transport.read(uid:uid,day:iraqDay);
    _check(uid, isCurrent);
    if (record == null) throw StateError('no-quiz-cloud-backup');
    const expectedKeys = {
      'format','kind','uid','accountKey','originalId','day','encoded','createdAt'
    };
    if (record.keys.toSet().difference(expectedKeys).isNotEmpty ||
        !expectedKeys.every(record.containsKey) ||
        record['format'] != 1 ||
        record['kind'] != 'display-only-untrusted-quiz-v1' ||
        record['uid'] != uid ||
        record['accountKey'] != accountKey ||
        record['originalId'] != originalId ||
        record['day'] != iraqDay ||
        record['encoded'] is! String) {
      throw const FormatException('quiz-cloud-archive-conflict');
    }
    final capture = DedaStep2UiCapture.decodeForAccount(
      record['encoded'] as String,
      accountKey:accountKey,originalId:originalId,iraqDay:iraqDay);
    if (capture.taskPointsRaw != null) {
      throw const FormatException('quiz-cloud-financial-payload-forbidden');
    }
    DedaQuizUiHydration.validateUiOnly(capture);
    await _owner(uid, accountKey, isCurrent);
    final changed = await uiHydration.restoreVerifiedUi(
      capture:capture,accountKey:accountKey,originalId:originalId,
      iraqDay:iraqDay,ownerUid:uid,currentUid:currentUid() ?? '',
      isCurrent:isCurrent,
    );
    _check(uid,isCurrent);
    return changed;
  }
}
