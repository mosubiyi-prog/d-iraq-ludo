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

/// Section 04/01: read-only profile data contract over the existing protected
/// snapshot. It does not mint, equip, edit, infer a full wallet or create a UID.
/// No local-phone fallback. The original profile renderer is still held until
/// its actual compiled callsites consume this contract.
class DedaStage04ProfileView {
  DedaStage04ProfileView._(this._source, this.acceptedFriends);
  final DedaStage03ProtectedSnapshot _source;
  final int acceptedFriends;
  String get uid => _source.uid;
  Map get _profile => _source.account['profile'] as Map;
  Map get _balances => _source.progress['balances'] as Map;
  String get displayName => _profile['displayName'] as String;
  String get originalId => _profile['originalId'] as String;
  String get activeId => _profile['activeId'] as String;
  String? get fixedColor => _profile['fixedColor'] as String?;
  int get taskPoints => _balances['points'] as int;
  int get coins => _balances['coins'] as int;
  int get xp => _balances['xp'] as int;
  // Only the protected earned balance, NOT the complete displayed wallet.
  int get earnedDiamonds => _balances['earnedDiamonds'] as int;
  List get frameRecords => _source.inventory['frames'] as List;
  List get identifierGiftRecords => _source.inventory['idGifts'] as List;
  List get diamondGiftRecords => _source.inventory['diamondGifts'] as List;
  /// Inventory projection is read-only. Require both records for a frame;
  /// a selection, bare ID, or unaccepted grant is not evidence of ownership.
  Set<String> get verifiedPaidFrameIds {
    final ids = <String>{};
    for (final row in frameRecords) {
      if (row is! Map || row.length != 3) {
        throw const FormatException('profile-frame-proof');
      }
      final id = row['frameId'], receipt = row['receipt'], ownership = row['ownership'];
      if (id is! String || !RegExp(r'^FRAME_(03|0[5-9]|1[0-6]) _source.account['revision'] as int;
  int get inventoryRevision => _source.inventory['revision'] as int;
  int get progressRevision => _source.progress['version'] as int;

  static DedaStage04ProfileView fromProtected(DedaStage03ProtectedSnapshot s) {
    final p = s.account['profile'] as Map;
    final color = p['fixedColor'];
    if (p['activeId'] == p['originalId']
        ? color != null
        : !const {'gold', 'diamond', 'royal', 'pink'}.contains(color)) {
      throw const FormatException('profile-id-color-inconsistent');
    }
    // Only a full accepted relationship involving this UID counts. Do not
    // substitute an empty list when a record is incomplete or duplicated.
    final peers = <String>{};
    var accepted = 0;
    for (final row in s.account['friends'] as List) {
      if (row is! Map) throw const FormatException('profile-invalid-friend');
      final a = row['requesterUid'], b = row['recipientUid'];
      final members = row['members'], status = row['status'];
      if (a is! String || b is! String || a.isEmpty || b.isEmpty ||
          a == b || (a != s.uid && b != s.uid) ||
          members is! List || members.length != 2 ||
          !members.contains(a) || !members.contains(b) ||
          !const {'pending','accepted','rejected'}.contains(status)) {
        throw const FormatException('profile-invalid-friend');
      }
      final pair = [a,b]..sort();
      if (row['pairKey'] != pair.join('__') ||
          !peers.add(a == s.uid ? b : a)) {
        throw const FormatException('profile-duplicate-or-invalid-friend');
      }
      if (status == 'accepted') accepted++;
    }
    return DedaStage04ProfileView._(s, accepted);
  }
}

/// A view admitted only by the current lab session. The caller must use
/// requireCurrent at presentation and action boundaries, not retain an old
/// view across a session transition.
class DedaStage04ProfileRead {
  DedaStage04ProfileRead._(this._view, this._current);
  final DedaStage04ProfileView _view;
  final bool Function() _current;
  DedaStage04ProfileView requireCurrent() {
    if (!_current()) throw const DedaPrivateDataStale();
    return _view;
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

  /// Stage 04/01 read binding, using the one existing session and storage
  /// transaction. No new collection, notifier, write or implicit login.
  static Future<DedaStage04ProfileRead> readProfile() async {
    final current = _intent();
    final protected = await readProtected();
    if (!current()) throw const DedaPrivateDataStale();
    final view = DedaStage04ProfileView.fromProtected(protected);
    if (!current()) throw const DedaPrivateDataStale();
    return DedaStage04ProfileRead._(view, current);
  }

  /// Profile Favorites/Activity: use the existing UID restore journal.
  /// Do not reinterpret a missing or conflicting field as an empty list.
  /// The original place renderer must independently decode each record.
  static Future<List<String>> readProfilePlaceRecords(
      DedaStage04ProfileRead profile, {required bool favorites}) async {
    profile.requireCurrent();
    final current = _intent();
    final result = await restore();
    if (!current()) throw const DedaPrivateDataStale();
    profile.requireCurrent();
    final key = favorites ? 'favorites' : 'recent';
    final records = result.revision.payload?.fields[key];
    if (result.status != DedaPrivateDataStatus.saved ||
        records is! List || !records.every((v) => v is String)) {
      throw StateError('stage04-profile-places-not-confirmed');
    }
    return List<String>.unmodifiable(records.cast<String>());
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
).hasMatch(id) ||
          receipt is! Map || receipt.length != 5 ||
          ownership is! Map || ownership.length != 4 ||
          receipt['uid'] != uid || ownership['uid'] != uid ||
          receipt['frameId'] != id || ownership['frameId'] != id ||
          receipt['kind'] != 'lab_frame' || receipt['cost'] != 1000 ||
          receipt['createdMs'] is! int || (receipt['createdMs'] as int) <= 0 ||
          receipt['createdMs'] != ownership['createdMs'] ||
          ownership['receiptId'] != '${uid}_$id' || !ids.add(id)) {
        throw const FormatException('profile-frame-proof');
      }
    }
    return Set.unmodifiable(ids);
  }

  Set<String> get acceptedGiftIds {
    final seen = <String>{}, accepted = <String>{};
    for (final row in identifierGiftRecords) {
      if (row is! Map || row.length != 3 || !row.containsKey('acceptance')) {
        throw const FormatException('profile-id-gift-proof');
      }
      final id = row['identifier'], grant = row['grant'], acceptance = row['acceptance'];
      if (id is! String || !RegExp(r'^@DEDA-[A-Z0-9]{4,12} _source.account['revision'] as int;
  int get inventoryRevision => _source.inventory['revision'] as int;
  int get progressRevision => _source.progress['version'] as int;

  static DedaStage04ProfileView fromProtected(DedaStage03ProtectedSnapshot s) {
    final p = s.account['profile'] as Map;
    final color = p['fixedColor'];
    if (p['activeId'] == p['originalId']
        ? color != null
        : !const {'gold', 'diamond', 'royal', 'pink'}.contains(color)) {
      throw const FormatException('profile-id-color-inconsistent');
    }
    // Only a full accepted relationship involving this UID counts. Do not
    // substitute an empty list when a record is incomplete or duplicated.
    final peers = <String>{};
    var accepted = 0;
    for (final row in s.account['friends'] as List) {
      if (row is! Map) throw const FormatException('profile-invalid-friend');
      final a = row['requesterUid'], b = row['recipientUid'];
      final members = row['members'], status = row['status'];
      if (a is! String || b is! String || a.isEmpty || b.isEmpty ||
          a == b || (a != s.uid && b != s.uid) ||
          members is! List || members.length != 2 ||
          !members.contains(a) || !members.contains(b) ||
          !const {'pending','accepted','rejected'}.contains(status)) {
        throw const FormatException('profile-invalid-friend');
      }
      final pair = [a,b]..sort();
      if (row['pairKey'] != pair.join('__') ||
          !peers.add(a == s.uid ? b : a)) {
        throw const FormatException('profile-duplicate-or-invalid-friend');
      }
      if (status == 'accepted') accepted++;
    }
    return DedaStage04ProfileView._(s, accepted);
  }
}

/// A view admitted only by the current lab session. The caller must use
/// requireCurrent at presentation and action boundaries, not retain an old
/// view across a session transition.
class DedaStage04ProfileRead {
  DedaStage04ProfileRead._(this._view, this._current);
  final DedaStage04ProfileView _view;
  final bool Function() _current;
  DedaStage04ProfileView requireCurrent() {
    if (!_current()) throw const DedaPrivateDataStale();
    return _view;
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

  /// Stage 04/01 read binding, using the one existing session and storage
  /// transaction. No new collection, notifier, write or implicit login.
  static Future<DedaStage04ProfileRead> readProfile() async {
    final current = _intent();
    final protected = await readProtected();
    if (!current()) throw const DedaPrivateDataStale();
    final view = DedaStage04ProfileView.fromProtected(protected);
    if (!current()) throw const DedaPrivateDataStale();
    return DedaStage04ProfileRead._(view, current);
  }

  /// Profile Favorites/Activity: use the existing UID restore journal.
  /// Do not reinterpret a missing or conflicting field as an empty list.
  /// The original place renderer must independently decode each record.
  static Future<List<String>> readProfilePlaceRecords(
      DedaStage04ProfileRead profile, {required bool favorites}) async {
    profile.requireCurrent();
    final current = _intent();
    final result = await restore();
    if (!current()) throw const DedaPrivateDataStale();
    profile.requireCurrent();
    final key = favorites ? 'favorites' : 'recent';
    final records = result.revision.payload?.fields[key];
    if (result.status != DedaPrivateDataStatus.saved ||
        records is! List || !records.every((v) => v is String)) {
      throw StateError('stage04-profile-places-not-confirmed');
    }
    return List<String>.unmodifiable(records.cast<String>());
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
).hasMatch(id) ||
          grant is! Map || grant.length != 6 || grant['uid'] != uid ||
          grant['identifier'] != id || grant['kind'] != 'gifted' ||
          !const {'001','002'}.contains(grant['group']) ||
          !const {'gold','diamond','royal','pink'}.contains(grant['baseColor']) ||
          grant['grantedMs'] is! int || (grant['grantedMs'] as int) <= 0 ||
          !seen.add(id)) {
        throw const FormatException('profile-id-gift-proof');
      }
      if (acceptance != null) {
        if (acceptance is! Map || acceptance.length != 4 ||
            acceptance['uid'] != uid || acceptance['identifier'] != id ||
            acceptance['group'] != grant['group'] ||
            acceptance['receivedMs'] is! int ||
            (acceptance['receivedMs'] as int) < (grant['grantedMs'] as int)) {
          throw const FormatException('profile-id-acceptance-proof');
        }
        accepted.add(id);
      }
    }
    return Set.unmodifiable(accepted);
  }
  int get accountRevision => _source.account['revision'] as int;
  int get inventoryRevision => _source.inventory['revision'] as int;
  int get progressRevision => _source.progress['version'] as int;

  static DedaStage04ProfileView fromProtected(DedaStage03ProtectedSnapshot s) {
    final p = s.account['profile'] as Map;
    final color = p['fixedColor'];
    if (p['activeId'] == p['originalId']
        ? color != null
        : !const {'gold', 'diamond', 'royal', 'pink'}.contains(color)) {
      throw const FormatException('profile-id-color-inconsistent');
    }
    // Only a full accepted relationship involving this UID counts. Do not
    // substitute an empty list when a record is incomplete or duplicated.
    final peers = <String>{};
    var accepted = 0;
    for (final row in s.account['friends'] as List) {
      if (row is! Map) throw const FormatException('profile-invalid-friend');
      final a = row['requesterUid'], b = row['recipientUid'];
      final members = row['members'], status = row['status'];
      if (a is! String || b is! String || a.isEmpty || b.isEmpty ||
          a == b || (a != s.uid && b != s.uid) ||
          members is! List || members.length != 2 ||
          !members.contains(a) || !members.contains(b) ||
          !const {'pending','accepted','rejected'}.contains(status)) {
        throw const FormatException('profile-invalid-friend');
      }
      final pair = [a,b]..sort();
      if (row['pairKey'] != pair.join('__') ||
          !peers.add(a == s.uid ? b : a)) {
        throw const FormatException('profile-duplicate-or-invalid-friend');
      }
      if (status == 'accepted') accepted++;
    }
    return DedaStage04ProfileView._(s, accepted);
  }
}

/// A view admitted only by the current lab session. The caller must use
/// requireCurrent at presentation and action boundaries, not retain an old
/// view across a session transition.
class DedaStage04ProfileRead {
  DedaStage04ProfileRead._(this._view, this._current);
  final DedaStage04ProfileView _view;
  final bool Function() _current;
  DedaStage04ProfileView requireCurrent() {
    if (!_current()) throw const DedaPrivateDataStale();
    return _view;
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

  /// Stage 04/01 read binding, using the one existing session and storage
  /// transaction. No new collection, notifier, write or implicit login.
  static Future<DedaStage04ProfileRead> readProfile() async {
    final current = _intent();
    final protected = await readProtected();
    if (!current()) throw const DedaPrivateDataStale();
    final view = DedaStage04ProfileView.fromProtected(protected);
    if (!current()) throw const DedaPrivateDataStale();
    return DedaStage04ProfileRead._(view, current);
  }

  /// Profile Favorites/Activity: use the existing UID restore journal.
  /// Do not reinterpret a missing or conflicting field as an empty list.
  /// The original place renderer must independently decode each record.
  static Future<List<String>> readProfilePlaceRecords(
      DedaStage04ProfileRead profile, {required bool favorites}) async {
    profile.requireCurrent();
    final current = _intent();
    final result = await restore();
    if (!current()) throw const DedaPrivateDataStale();
    profile.requireCurrent();
    final key = favorites ? 'favorites' : 'recent';
    final records = result.revision.payload?.fields[key];
    if (result.status != DedaPrivateDataStatus.saved ||
        records is! List || !records.every((v) => v is String)) {
      throw StateError('stage04-profile-places-not-confirmed');
    }
    return List<String>.unmodifiable(records.cast<String>());
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
