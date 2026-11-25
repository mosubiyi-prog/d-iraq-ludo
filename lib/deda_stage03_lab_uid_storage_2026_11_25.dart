import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'deda_auth_session_runtime.dart';
import 'deda_private_data_sync.dart';
import 'deda_stage02_lab_single_uid_2026_11_25.dart';

/// Read-only envelope. Only the guarded server transaction establishes source
/// provenance; decoding a map never grants rewards, money, ownership or roles.
class DedaStage03ProtectedSnapshot {
  DedaStage03ProtectedSnapshot._(this.uid, this.progress, this.inventory, this.account);
  final String uid;
  final Map<String, Object?> progress, inventory, account;

  static bool _exact(Map<String, Object?> m, Set<String> keys) =>
      m.length == keys.length && keys.every(m.containsKey);
  static bool _counter(Object? v, {int min = 0}) =>
      v is int && v >= min && v <= 9007199254740990;
  static Object? _freeze(Object? v) {
    if (v is Map) {
      return Map<String, Object?>.unmodifiable({
        for (final e in v.entries) e.key as String: _freeze(e.value),
      });
    }
    if (v is List) return List<Object?>.unmodifiable(v.map(_freeze));
    if (v == null || v is String || v is bool || v is num) return v;
    throw const FormatException('unsupported-protected-field');
  }
  static DedaStage03ProtectedSnapshot decode({
    required String expectedUid,
    required Map<String, Object?>? progress,
    required Map<String, Object?>? inventory,
    required Map<String, Object?>? account,
  }) {
    if (expectedUid != DedaStage02LabSingleUid.approvedUid ||
        progress == null || inventory == null || account == null) {
      throw const FormatException('protected-source-incomplete');
    }
    final balances = progress['balances'];
    const units = {'points', 'coins', 'xp', 'earnedDiamonds'};
    if (!_exact(progress, {'format','accountKey','version','balances','initializedBy'}) ||
        progress['format'] != 1 || progress['accountKey'] != expectedUid ||
        !_counter(progress['version'], min: 1) || balances is! Map ||
        balances.length != units.length || !units.every((k) => _counter(balances[k])) ||
        progress['initializedBy'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(progress['initializedBy'] as String)) {
      throw const FormatException('invalid-protected-progress');
    }
    bool validProjection(Map<String, Object?> row, Set<String> fields) =>
        _exact(row, {'format','uid','revision','complete',...fields}) &&
        row['format'] == 1 && row['uid'] == expectedUid &&
        _counter(row['revision'], min: 1) && row['complete'] == true;
    if (!validProjection(inventory, {'frames','idGifts','diamondGifts'}) ||
        !['frames','idGifts','diamondGifts'].every((k) => inventory[k] is List)) {
      throw const FormatException('invalid-protected-inventory');
    }
    final profile = account['profile'];
    if (!validProjection(account, {'profile','friends','tasks','league'}) ||
        profile is! Map || profile.length != 4 ||
        !['displayName','originalId','activeId','fixedColor'].every(profile.containsKey) ||
        profile['displayName'] is! String || (profile['displayName'] as String).trim().isEmpty ||
        profile['originalId'] is! String ||
        !RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(profile['originalId'] as String) ||
        profile['activeId'] is! String ||
        !RegExp(r'^@DEDA-[A-Z0-9]{4,12}$').hasMatch(profile['activeId'] as String) ||
        !['friends','tasks','league'].every((k) => account[k] is List)) {
      throw const FormatException('invalid-protected-account');
    }
    return DedaStage03ProtectedSnapshot._(expectedUid,
        _freeze(progress) as Map<String, Object?>,
        _freeze(inventory) as Map<String, Object?>,
        _freeze(account) as Map<String, Object?>);
  }
}

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

  /// Server transaction reads all protected views under the same UID.
  /// No write, no partial or cached fallback if a source is unavailable.
  static Future<DedaStage03ProtectedSnapshot> readProtected() async {
    final current = _intent();
    void check() {
      if (!current()) throw const DedaPrivateDataStale();
      _io._check(uid, uid);
    }
    await _io.verifyOwner(uid, uid, check);
    check();
    final db = FirebaseFirestore.instanceFor(app: Firebase.app());
    final base = db.doc('deda_lab_uid_authority/$uid');
    final result = await db.runTransaction<DedaStage03ProtectedSnapshot>((tx) async {
      check();
      final p = await tx.get(base);
      check();
      final i = await tx.get(base.collection('inventory').doc('current'));
      check();
      final a = await tx.get(base.collection('account').doc('current'));
      check();
      for (final row in [p,i,a]) {
        if (!row.exists || row.metadata.isFromCache || row.metadata.hasPendingWrites) {
          throw StateError('protected-server-source-required');
        }
      }
      return DedaStage03ProtectedSnapshot.decode(expectedUid: uid,
          progress: p.data(), inventory: i.data(), account: a.data());
    }, timeout: const Duration(seconds: 15));
    check();
    return result;
  }

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
