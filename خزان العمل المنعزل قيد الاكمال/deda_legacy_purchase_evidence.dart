import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'deda_progress_evidence_store.dart';
import 'deda_owner_session_firebase_port.dart';
import 'deda_session_flow_prototype.dart';
import 'deda_session_transition_gate.dart';

const dedaLegacyPurchaseFrames = <String>[
  'FRAME_03', 'FRAME_05', 'FRAME_06', 'FRAME_07', 'FRAME_08',
  'FRAME_09', 'FRAME_10', 'FRAME_11', 'FRAME_12', 'FRAME_13',
  'FRAME_14', 'FRAME_15', 'FRAME_16',
];
void _scope(String account, String original) {
  if (!RegExp(r'^[0-9]+$').hasMatch(account) ||
      !RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(original)) {
    throw const FormatException('invalid-purchase-evidence-scope');
  }
}
void _id(String value) {
  if (!RegExp(r'^[A-Za-z0-9_-]{20,80}$').hasMatch(value)) {
    throw const FormatException('invalid-purchase-capture-id');
  }
}
Object? _value(Object? value) {
  if (value == null || value is String || value is bool || value is int) return value;
  if (value is double && value.isFinite) return value;
  if (value is List && value.every((item) => item is String)) {
    return List<String>.unmodifiable(value.cast<String>());
  }
  throw const FormatException('unsupported-native-purchase-value');
}

abstract class DedaLegacyPurchaseReadStore {
  Future<Map<String, Object?>> readValues(List<String> keys);
}
class DedaSharedPreferencesPurchaseReadStore implements DedaLegacyPurchaseReadStore {
  @override
  Future<Map<String, Object?>> readValues(List<String> keys) async {
    final prefs = await SharedPreferences.getInstance();
    // get preserves unexpected native types. Never call checkout/wallet code,
    // clear, set, migrate, repair, or default a missing value to a paid state.
    return {for (final key in keys) key: prefs.get(key)};
  }
}

/// Untrusted local evidence only; no receipt, refund, or ownership authority.
class DedaLegacyPurchaseCapture {
  DedaLegacyPurchaseCapture._(this.accountKey, this.originalId, Object? inventory,
      Map<String, Object?> journals)
      : inventory = _value(inventory),
        journals = Map.unmodifiable(journals.map((key, value) => MapEntry(key, _value(value))));
  final String accountKey, originalId;
  final Object? inventory;
  final Map<String, Object?> journals;
  String encode() => jsonEncode({'format': 1, 'accountKey': accountKey,
    'originalId': originalId, 'inventory': inventory, 'frameJournals': journals});
  static DedaLegacyPurchaseCapture decode(String text, {
      required String accountKey, required String originalId}) {
    _scope(accountKey, originalId);
    final dynamic decoded = jsonDecode(text);
    const keys = {'format', 'accountKey', 'originalId', 'inventory', 'frameJournals'};
    if (decoded is! Map || decoded.length != keys.length ||
        !keys.every(decoded.containsKey) || decoded['format'] != 1 ||
        decoded['accountKey'] != accountKey || decoded['originalId'] != originalId ||
        decoded['frameJournals'] is! Map) {
      throw const FormatException('invalid-purchase-snapshot');
    }
    final journals = decoded['frameJournals'] as Map;
    if (journals.length != dedaLegacyPurchaseFrames.length ||
        !dedaLegacyPurchaseFrames.every(journals.containsKey)) {
      throw const FormatException('invalid-purchase-journals');
    }
    return DedaLegacyPurchaseCapture._(accountKey, originalId, decoded['inventory'],
      {for (final frame in dedaLegacyPurchaseFrames) frame: journals[frame]});
  }
}
class DedaLegacyPurchaseReader {
  DedaLegacyPurchaseReader(this.store);
  final DedaLegacyPurchaseReadStore store;
  Future<DedaLegacyPurchaseCapture> capture({required String accountKey,
      required String originalId, required bool Function() isCurrent}) async {
    _scope(accountKey, originalId);
    void check() { if (!isCurrent()) throw const DedaStaleSessionTransition(); }
    check();
    final inventoryKey = 'deda_style_inventory_v1_$accountKey';
    final journalKeys = {for (final frame in dedaLegacyPurchaseFrames)
      frame: 'deda_native_frame_pending_v1_${originalId}_$frame'};
    final keys = [inventoryKey, ...journalKeys.values];
    final values = await store.readValues(List.unmodifiable(keys));
    check();
    if (values.length != keys.length || !keys.every(values.containsKey)) {
      throw const FormatException('incomplete-purchase-read');
    }
    final result = DedaLegacyPurchaseCapture._(accountKey, originalId, values[inventoryKey],
      {for (final entry in journalKeys.entries) entry.key: values[entry.value]});
    if (utf8.encode(result.encode()).length > 200000) {
      throw const FormatException('purchase-evidence-too-large');
    }
    check();
    return result;
  }
}
class DedaStoredPurchaseEvidence {
  const DedaStoredPurchaseEvidence({required this.captureId,
    required this.progressCaptureId, required this.capture,
    required this.sourceUid, required this.installId, required this.createdAt});
  final String captureId, progressCaptureId, sourceUid, installId;
  final DedaLegacyPurchaseCapture capture;
  final Timestamp createdAt;
}

/// UNWIRED sidecar archive. Reuses read-only account proof and immutable
/// transport, with a separate path/kind; never changes the old archive schema.
/// Caller MUST retain the same capture ID/payload after uncertain transport.
/// This class does not retry, create auth sessions, restore, or settle money.
class DedaLegacyPurchaseEvidenceStore {
  DedaLegacyPurchaseEvidenceStore(this.progress);
  final DedaProgressEvidenceStore progress;
  DedaProgressEvidenceIo get io => progress.io;
  String _path(String account, String id) => 'deda_purchase_evidence/$account/captures/$id';
  void _check(DedaFlowSdkUser user, bool Function() isCurrent) {
    final live = io.currentUser;
    if (!isCurrent() || !io.ready || live == null ||
        live.kind != DedaSessionAuthKind.anonymous || live.uid != user.uid ||
        live.kind != user.kind || live.revision != user.revision) {
      throw const DedaStaleSessionTransition();
    }
  }
  Map<String, dynamic> _server(DedaOwnerServerDocument doc) {
    if (doc.fromCache || doc.pendingWrites) throw const DedaSessionProofRejected();
    if (doc.data == null) throw const DedaProgressEvidenceMissing();
    return doc.data!;
  }
  bool _same(Map<String, dynamic> a, Map<String, dynamic> b) =>
    ['format', 'kind', 'accountKey', 'sourceUid', 'installId', 'captureId']
      .every((key) => a[key] == b[key]) &&
    a['records'] is Map && b['records'] is Map &&
    (a['records'] as Map).length == (b['records'] as Map).length &&
    (a['records'] as Map).keys.every((key) => (a['records'] as Map)[key] == (b['records'] as Map)[key]);
  DedaStoredPurchaseEvidence _decode(String account, String id, Map<String, dynamic> data) {
    const keys = {'format', 'kind', 'accountKey', 'sourceUid', 'installId', 'captureId', 'records', 'createdAt'};
    if (data.length != keys.length || !keys.every(data.containsKey) || data['format'] != 1 ||
        data['kind'] != 'legacy-purchase-evidence' || data['accountKey'] != account || data['captureId'] != id ||
        data['sourceUid'] is! String || (data['sourceUid'] as String).isEmpty ||
        data['installId'] is! String || (data['installId'] as String).isEmpty ||
        (data['installId'] as String).length > 128 || data['createdAt'] is! Timestamp || data['records'] is! Map) {
      throw const FormatException('invalid-purchase-evidence');
    }
    final r = data['records'] as Map;
    if (r.length != 3 || !['originalId', 'progressCaptureId', 'localSnapshot'].every(r.containsKey) ||
        r['originalId'] is! String || r['progressCaptureId'] is! String || r['localSnapshot'] is! String ||
        utf8.encode(r['localSnapshot'] as String).length > 200000) {
      throw const FormatException('invalid-purchase-records');
    }
    _id(r['progressCaptureId'] as String);
    final capture = DedaLegacyPurchaseCapture.decode(r['localSnapshot'] as String,
      accountKey: account, originalId: r['originalId'] as String);
    if (capture.encode() != r['localSnapshot']) throw const FormatException('noncanonical-purchase-snapshot');
    return DedaStoredPurchaseEvidence(captureId: id, progressCaptureId: r['progressCaptureId'] as String,
      capture: capture,
      sourceUid: data['sourceUid'] as String, installId: data['installId'] as String,
      createdAt: data['createdAt'] as Timestamp);
  }
  Future<DedaStoredPurchaseEvidence> save({required String captureId,
      required String progressCaptureId, required DedaLegacyPurchaseCapture capture,
      required bool Function() isCurrent}) async {
    _id(captureId); _id(progressCaptureId);
    final text = capture.encode();
    if (utf8.encode(text).length > 200000) throw const FormatException('purchase-evidence-too-large');
    final owner = await progress.verifyCurrentOwner(accountKey: capture.accountKey, isCurrent: isCurrent);
    void check() => _check(owner.user, isCurrent);
    check();
    final parent = await progress.read(accountKey: capture.accountKey,
      captureId: progressCaptureId, isCurrent: () { check(); return true; });
    check();
    if (parent.sourceUid != owner.user.uid || parent.installId != owner.installId) {
      throw const DedaSessionProofRejected();
    }
    final profile = _server(await io.readServer('users/${owner.user.uid}')); check();
    // The sidecar CREATE rules atomically verify personal route/owner account.
    // No additional read permission is added to existing routing collections.
    if (profile['sharePersonalId'] != capture.originalId) {
      throw const DedaSessionProofRejected();
    }
    final fields = <String, dynamic>{'format': 1, 'kind': 'legacy-purchase-evidence',
      'accountKey': capture.accountKey, 'sourceUid': owner.user.uid, 'installId': owner.installId,
      'captureId': captureId, 'records': {'originalId': capture.originalId,
        'progressCaptureId': progressCaptureId, 'localSnapshot': text}, 'createdAt': io.serverTimestamp()};
    check();
    await io.writeOnce(_path(capture.accountKey, captureId), fields, check); check();
    final saved = _server(await io.readServer(_path(capture.accountKey, captureId))); check();
    if (!_same(saved, fields)) throw const DedaProgressEvidenceConflict();
    return _decode(capture.accountKey, captureId, saved);
  }
  Future<DedaStoredPurchaseEvidence> read({required String accountKey,
      required String captureId, required bool Function() isCurrent}) async {
    _id(captureId);
    final owner = await progress.verifyCurrentOwner(accountKey: accountKey, isCurrent: isCurrent);
    _check(owner.user, isCurrent);
    final data = _server(await io.readServer(_path(accountKey, captureId)));
    _check(owner.user, isCurrent);
    return _decode(accountKey, captureId, data);
  }
}
