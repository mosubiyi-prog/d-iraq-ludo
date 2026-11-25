import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'deda_auth_session_runtime.dart';
import 'deda_private_data_sync.dart';
import 'deda_stage02_lab_single_uid_2026_11_25.dart';

/// Lab only, default off. No legacy account/phone/ID routing, no wallet,
/// rewards, role, ownership or authoritative score writes from this class.
/// Existing DedaPrivateDataSync provides revision and journal coordination.
class DedaStage03LabStorage implements DedaPrivateDataIo {
  DedaStage03LabStorage._();
  static const enabled = bool.fromEnvironment('DEDA_STAGE03_LAB_STORAGE');
  static const uid = DedaStage02LabSingleUid.approvedUid;
  static final _io = DedaStage03LabStorage._();
  static final _sync = DedaPrivateDataSync.uidScoped(_io);

  static bool _matches() {
    try {
      return enabled && DedaStage02LabSingleUid.inspect(expectedUid: uid) == uid;
    } catch (_) { return false; }
  }
  static bool Function() _intent() {
    if (!_matches()) throw StateError('stage03-lab-identity-required');
    final snapshot = DedaAuthRuntime.capture();
    return () {
      try {
        return _matches() && snapshot != null &&
            snapshot.matches(DedaAuthRuntime.capture()!);
      } catch (_) { return false; }
    };
  }

  static Future<DedaPrivateDataResult> backup(DedaPrivateDataPayload payload) =>
      _sync.backup(account: uid, original: uid, payload: payload, isCurrent: _intent());
  static Future<DedaPrivateDataResult> restore() =>
      _sync.restore(account: uid, original: uid, isCurrent: _intent());

  void _check(String account, [String? original]) {
    if (!_matches() || account != uid || (original != null && original != uid)) {
      throw const DedaPrivateDataStale();
    }
  }

  String _key(String account) => 'deda_stage03_lab_uid_journal_v1_$account';
  DocumentReference<Map<String, dynamic>> _head(String account) {
    _check(account);
    return FirebaseFirestore.instanceFor(app: Firebase.app())
        .doc('deda_lab_uid_private/$account');
  }

  @override
  String newMutationId() {
    final rng = Random.secure();
    return List.generate(24, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }
  @override
  Future<String?> readJournal(String account) async {
    _check(account);
    final prefs = await SharedPreferences.getInstance();
    _check(account);
    return prefs.getString(_key(account));
  }
  @override
  Future<void> writeJournal(String account, String text) async {
    _check(account);
    final prefs = await SharedPreferences.getInstance();
    _check(account);
    if (!await prefs.setString(_key(account), text)) throw StateError('journal-write-failed');
    _check(account);
  }
  @override
  Future<void> preserveJournal(String account, String text) async {
    _check(account);
    final prefs = await SharedPreferences.getInstance();
    _check(account);
    if (!await prefs.setString('${_key(account)}_archive_${newMutationId()}', text)) {
      throw StateError('journal-preserve-failed');
    }
    _check(account);
  }
  @override
  Future<void> verifyOwner(String account, String original, void Function() check) async {
    check(); _check(account, original);
    final token = await FirebaseAuth.instance.currentUser!.getIdToken(true)
        .timeout(const Duration(seconds: 15));
    check(); _check(account, original);
    if (token == null || token.isEmpty) throw StateError('server-auth-required');
  }

  DedaPrivateDataRevision _decode(DocumentSnapshot<Map<String, dynamic>> snap) {
    if (snap.metadata.isFromCache || snap.metadata.hasPendingWrites) {
      throw StateError('server-revision-required');
    }
    if (!snap.exists) return const DedaPrivateDataRevision(0, null, null);
    final d = snap.data();
    const fields = {'format','uid','version','mutationId','payload','updatedAt'};
    if (d == null || d.length != fields.length || !fields.every(d.containsKey) ||
        d['format'] != 1 || d['uid'] != uid || d['version'] is! int ||
        d['mutationId'] is! String || d['payload'] is! String || d['updatedAt'] is! Timestamp) {
      throw const FormatException('invalid-lab-revision');
    }
    final revision = DedaPrivateDataRevision(d['version'] as int,
      d['mutationId'] as String, DedaPrivateDataPayload.decode(d['payload'] as String, uidScoped: true));
    revision.validate();
    return revision;
  }
  @override
  Future<DedaPrivateDataRevision> readServer(String account, String original, void Function() check) async {
    check(); _check(account, original);
    final snap = await _head(account).get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 15));
    check(); _check(account, original);
    return _decode(snap);
  }
  @override
  Future<DedaPrivateDataRevision> compareAndSet(String account, String original,
      int baseVersion, String mutationId, DedaPrivateDataPayload payload, void Function() check) async {
    check(); _check(account, original);
    final ref = _head(account);
    final receipt = ref.collection('versions').doc(mutationId);
    final db = FirebaseFirestore.instanceFor(app: Firebase.app());
    await db.runTransaction<void>((tx) async {
      check(); _check(account, original);
      final old = _decode(await tx.get(ref));
      check(); _check(account, original);
      if (old.mutationId == mutationId) {
        if (old.payload?.encode() != payload.encode()) throw const FormatException('replay-mismatch');
        return;
      }
      if (old.version != baseVersion) throw const DedaPrivateDataConflict();
      final prior = await tx.get(receipt);
      check(); _check(account, original);
      if (prior.exists) throw const DedaPrivateDataConflict();
      final data = <String,dynamic>{'format': 1, 'uid': uid, 'version': baseVersion+1,
        'mutationId': mutationId, 'payload': payload.encode(), 'updatedAt': FieldValue.serverTimestamp()};
      tx.set(ref,data); tx.set(receipt,data);
    });
    // No outer timeout/retry of a mutation. Read actual committed revision.
    check(); _check(account, original);
    return readServer(account, original, check);
  }
}
