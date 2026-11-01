import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'deda_100431_linked_owner_session_policy.dart';

/// Original-account scoped local place evidence ONLY. It cannot restore
/// approval, reassign ownerUid, create map places or grant edit access.
/// Not connected to any user build unless a separately approved private pilot
/// enables it and deployed Firestore rules are verified on two devices.
const bool dedaStep2OwnerPlaceLocalArchiveEnabled = bool.fromEnvironment(
  'DEDA_STEP2_OWNER_PLACE_LOCAL_ARCHIVE', defaultValue: false);

class DedaStep2OwnerPlaceArchiveHold implements Exception {
  const DedaStep2OwnerPlaceArchiveHold(this.reason);
  final String reason;
  @override
  String toString() => 'DedaStep2OwnerPlaceArchiveHold($reason)';
}

/// Exact four account-scoped SharedPreferences keys used by OwnerPlacePage.
/// NEVER read legacy unscoped keys or deda_personal_places_v1, because those
/// may belong to another user of the same handset.
const dedaStep2OwnerPlaceSourceKeys = <String>[
  'placeId', 'pendingEditId', 'draftRaw', 'submittedRaw',
];
String _sourceKey(String field, String account) => switch (field) {
  'placeId' => 'deda_owner_place_id_v2_$account',
  'pendingEditId' => 'deda_owner_pending_edit_id_v2_$account',
  'draftRaw' => 'deda_owner_place_draft_v1_$account',
  'submittedRaw' => 'deda_owner_submitted_snapshot_v2_$account',
  _ => throw ArgumentError('unknown-place-source'),
};

abstract class DedaStep2OwnerPlaceLocalIo {
  Future<Map<String, String?>> readExact(List<String> keys);
}

class DedaStep2OwnerPlaceSharedLocal implements DedaStep2OwnerPlaceLocalIo {
  const DedaStep2OwnerPlaceSharedLocal();
  @override
  Future<Map<String, String?>> readExact(List<String> keys) async {
    final prefs = await SharedPreferences.getInstance();
    // A corrupt native type throws instead of being silently replaced.
    return {for (final key in keys) key: prefs.getString(key)};
  }
}

class DedaStep2OwnerPlaceSource {
  DedaStep2OwnerPlaceSource._(this.accountKey, Map<String, String?> records)
      : records = Map.unmodifiable(records);

  final String accountKey;
  final Map<String, String?> records;
  bool get hasAnyEvidence => records.values.any((value) => value != null);
  bool get canRestoreMapOwnership => false;
  bool get canApprovePlace => false;
  bool get canCreatePlace => false;

  Map<String, String?> toRecords() => Map.unmodifiable(records);

  static DedaStep2OwnerPlaceSource checked(
      String account, Map<String, dynamic> value) {
    if (!RegExp(r'^[0-9]{8,16}$').hasMatch(account) ||
        value.length != dedaStep2OwnerPlaceSourceKeys.length ||
        !dedaStep2OwnerPlaceSourceKeys.every(value.containsKey)) {
      throw const DedaStep2OwnerPlaceArchiveHold('place-scope-incomplete');
    }
    final data = <String, String?>{};
    for (final field in dedaStep2OwnerPlaceSourceKeys) {
      final raw = value[field];
      if (raw != null && raw is! String) {
        throw const DedaStep2OwnerPlaceArchiveHold('wrong-place-native-type');
      }
      final fieldText = raw as String?;
      if (fieldText != null && utf8.encode(fieldText).length >
          (field == 'placeId' || field == 'pendingEditId' ? 256 : 65536)) {
        throw const DedaStep2OwnerPlaceArchiveHold('place-evidence-too-large');
      }
      if (fieldText != null && (field == 'placeId' ||
          field == 'pendingEditId') && (fieldText.contains('/') ||
          fieldText.trim().isEmpty)) {
        throw const DedaStep2OwnerPlaceArchiveHold('invalid-place-reference');
      }
      // A malformed draft is preserved verbatim as evidence, not corrected,
      // published, or used to overwrite existing documents.
      data[field] = fieldText;
    }
    return DedaStep2OwnerPlaceSource._(account, data);
  }

  static Future<DedaStep2OwnerPlaceSource> readOriginal(
      DedaStep2OwnerPlaceLocalIo io, {
      required String accountKey, required bool Function() isCurrent}) async {
    if (!isCurrent()) {
      throw const DedaStep2OwnerPlaceArchiveHold('place-session-changed');
    }
    final keys = [
      for (final field in dedaStep2OwnerPlaceSourceKeys)
        _sourceKey(field, accountKey),
    ];
    final values = await io.readExact(List.unmodifiable(keys));
    if (!isCurrent() || values.length != keys.length ||
        keys.any((key) => !values.containsKey(key))) {
      throw const DedaStep2OwnerPlaceArchiveHold('place-local-read-incomplete');
    }
    return checked(accountKey, {
      for (final field in dedaStep2OwnerPlaceSourceKeys)
        field: values[_sourceKey(field, accountKey)],
    });
  }
}

class DedaStep2OwnerPlaceServerRow {
  const DedaStep2OwnerPlaceServerRow(this.data,
      {this.fromCache = false, this.pendingWrites = false});
  final Map<String, dynamic>? data;
  final bool fromCache, pendingWrites;
}

/// Compare fields semantically, never using JSON map insertion order from
/// Firestore, which is not guaranteed to match the source map order.
bool _sameArchiveBody(Map<String, dynamic> old,
    Map<String, dynamic> source) {
  const fields = ['format','kind','accountKey','sourceUid','captureId'];
  if (!fields.every((k) => old[k] == source[k])) return false;
  final records = old['records'];
  final expected = source['records'];
  if (records is! Map || expected is! Map ||
      records.length != dedaStep2OwnerPlaceSourceKeys.length ||
      expected.length != dedaStep2OwnerPlaceSourceKeys.length) {
    return false;
  }
  return dedaStep2OwnerPlaceSourceKeys.every((key) =>
      records.containsKey(key) && expected.containsKey(key) &&
      records[key] == expected[key]);
}

abstract class DedaStep2OwnerPlaceCloudIo {
  Future<DedaStep2OwnerPlaceServerRow> read(
      String accountKey, String captureId);
  Future<void> writeOnce(String accountKey, String captureId,
      Map<String, dynamic> source);
}

class DedaStep2OwnerPlaceFirestore implements DedaStep2OwnerPlaceCloudIo {
  const DedaStep2OwnerPlaceFirestore();

  DocumentReference<Map<String, dynamic>> _ref(
      String accountKey, String captureId) =>
      FirebaseFirestore.instance.collection('deda_step2_owner_place_evidence')
          .doc(accountKey).collection('captures').doc(captureId);

  @override
  Future<DedaStep2OwnerPlaceServerRow> read(
      String accountKey, String captureId) async {
    final doc = await _ref(accountKey, captureId)
        .get(const GetOptions(source: Source.server));
    return DedaStep2OwnerPlaceServerRow(doc.data(),
        fromCache: doc.metadata.isFromCache,
        pendingWrites: doc.metadata.hasPendingWrites);
  }

  @override
  Future<void> writeOnce(String accountKey, String captureId,
      Map<String, dynamic> source) async {
    await FirebaseFirestore.instance.runTransaction<void>((tx) async {
      final ref = _ref(accountKey, captureId);
      final existing = await tx.get(ref);
      if (existing.exists) {
        final recorded = existing.data() ?? {};
        if (recorded.length != source.length + 1 ||
            !_sameArchiveBody(recorded, source)) {
          throw const DedaStep2OwnerPlaceArchiveHold(
              'immutable-place-snapshot-conflict');
        }
        return;
      }
      tx.set(ref, {...source, 'createdAt': FieldValue.serverTimestamp()});
    });
  }
}

/// Read-back receipt is evidence, NOT permission to edit a published place.
/// The actual map place must still be separately verified with the original
/// UID and approval number before OwnerPlacePage displays editing controls.
class DedaStep2OwnerPlaceLocalArchive {
  const DedaStep2OwnerPlaceLocalArchive({
    required this.local,
    required this.cloud,
    required this.currentUid,
    required this.verifyOriginalOwner,
    this.enabled = dedaStep2OwnerPlaceLocalArchiveEnabled,
  });

  factory DedaStep2OwnerPlaceLocalArchive.firebase() =>
      DedaStep2OwnerPlaceLocalArchive(
        local: const DedaStep2OwnerPlaceSharedLocal(),
        cloud: const DedaStep2OwnerPlaceFirestore(),
        currentUid: () => FirebaseAuth.instance.currentUser?.uid,
        verifyOriginalOwner: (uid, account) async {
          final user = FirebaseAuth.instance.currentUser;
          return user?.uid == uid &&
              await DedaLinkedOwnerSessionPolicy.verified(user, account);
        },
      );

  final DedaStep2OwnerPlaceLocalIo local;
  final DedaStep2OwnerPlaceCloudIo cloud;
  final String? Function() currentUid;
  final Future<bool> Function(String uid, String accountKey)
      verifyOriginalOwner;
  final bool enabled;

  void _check(String account, String uid, bool Function() isCurrent) {
    if (!enabled || !RegExp(r'^[0-9]{8,16}$').hasMatch(account) ||
        uid.isEmpty || currentUid() != uid || !isCurrent()) {
      throw const DedaStep2OwnerPlaceArchiveHold(
          'original-owner-place-proof-required');
    }
  }

  /// Replacement handset: verified original user may INSPECT the old local
  /// evidence only. It must never be used to grant map editing privileges;
  /// those require published_places ownerUid and approval checks separately.
  Future<DedaStep2OwnerPlaceSource> inspectOnReplacementPhone({
    required String accountKey,
    required String originalUid,
    required String captureId,
    required bool Function() isCurrent,
  }) async {
    void check() => _check(accountKey, originalUid, isCurrent);
    if (!RegExp(r'^[A-Za-z0-9_-]{20,80}$').hasMatch(captureId)) {
      throw const DedaStep2OwnerPlaceArchiveHold('invalid-place-capture-id');
    }
    check();
    if (!await verifyOriginalOwner(originalUid, accountKey)) {
      throw const DedaStep2OwnerPlaceArchiveHold(
          'place-archive-owner-not-verified');
    }
    check();
    final row = await cloud.read(accountKey, captureId);
    check();
    final data = row.data;
    if (row.fromCache || row.pendingWrites || data == null ||
        data.length != 7 || data['format'] != 1 ||
        data['kind'] != 'untrusted-local-owner-place-evidence' ||
        data['accountKey'] != accountKey ||
        data['sourceUid'] != originalUid ||
        data['captureId'] != captureId ||
        data['createdAt'] is! Timestamp || data['records'] is! Map) {
      throw const DedaStep2OwnerPlaceArchiveHold(
          'place-archive-not-authoritative');
    }
    final source = DedaStep2OwnerPlaceSource.checked(
        accountKey, Map<String, dynamic>.from(data['records'] as Map));
    check();
    if (!source.hasAnyEvidence) {
      throw const DedaStep2OwnerPlaceArchiveHold('no-place-archive-records');
    }
    return source;
  }

  Future<DedaStep2OwnerPlaceSource> archiveOriginalPhone({
    required String accountKey,
    required String originalUid,
    required String captureId,
    required bool Function() isCurrent,
  }) async {
    void check() => _check(accountKey, originalUid, isCurrent);
    if (!RegExp(r'^[A-Za-z0-9_-]{20,80}$').hasMatch(captureId)) {
      throw const DedaStep2OwnerPlaceArchiveHold('invalid-place-capture-id');
    }
    check();
    if (!await verifyOriginalOwner(originalUid, accountKey)) {
      throw const DedaStep2OwnerPlaceArchiveHold(
          'place-archive-owner-not-verified');
    }
    check();
    final source = await DedaStep2OwnerPlaceSource.readOriginal(local,
        accountKey: accountKey, isCurrent: isCurrent);
    check();
    if (!source.hasAnyEvidence) {
      throw const DedaStep2OwnerPlaceArchiveHold('no-local-place-to-preserve');
    }
    final body = {
      'format': 1,
      'kind': 'untrusted-local-owner-place-evidence',
      'accountKey': accountKey,
      'sourceUid': originalUid,
      'captureId': captureId,
      'records': source.toRecords(),
    };
    // A lost write acknowledgement leaves captureId unresolved: the caller
    // MUST reuse this ID and original bytes; it may not claim success.
    await cloud.writeOnce(accountKey, captureId, body);
    check();
    final stored = await cloud.read(accountKey, captureId);
    check();
    final data = stored.data;
    if (stored.fromCache || stored.pendingWrites || data == null ||
        data.length != body.length + 1 ||
        data['createdAt'] is! Timestamp ||
        !_sameArchiveBody(data, body)) {
      throw const DedaStep2OwnerPlaceArchiveHold(
          'place-archive-server-readback-mismatch');
    }
    return source;
  }
}
