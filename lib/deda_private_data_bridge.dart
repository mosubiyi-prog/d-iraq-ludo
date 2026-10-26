import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'deda_account_choice_firebase.dart';
import 'deda_auth_session_runtime.dart';
import 'deda_backend.dart';
import 'deda_private_data_sync.dart';
import 'deda_section_operation_context.dart';
import 'deda_session_transition_gate.dart';
import 'main.dart' show DedaPreferences;

const dedaPrivateDataEnabled = bool.fromEnvironment('DEDA_STABILITY_PRIVATE_DATA', defaultValue: false);

class DedaFirebasePrivateDataIo implements DedaPrivateDataIo {
  String _key(String account) => 'deda_private_data_journal_v1_$account';
  @override
  String newMutationId() {
    final random = Random.secure();
    return List.generate(24, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }
  @override
  Future<String?> readJournal(String account) async =>
      (await SharedPreferences.getInstance()).getString(_key(account));
  @override
  Future<void> writeJournal(String account, String text) async {
    if (!await (await SharedPreferences.getInstance()).setString(_key(account), text)) {
      throw StateError('private-data-journal-not-saved');
    }
  }
  @override
  Future<void> preserveJournal(String account, String text) async {
    if (!await (await SharedPreferences.getInstance()).setString(
        'deda_private_data_archive_v1_${account}_${newMutationId()}', text)) {
      throw StateError('private-data-archive-not-saved');
    }
  }
  @override
  Future<void> verifyOwner(String account, String original, void Function() check) =>
      DedaFirebaseAccountChoiceIo().verifyOwner(account, original, check)
          .timeout(const Duration(seconds: 12));
  DedaPrivateDataRevision _decode(DocumentSnapshot<Map<String, dynamic>> snapshot,
      String account, String original) {
    if (snapshot.metadata.isFromCache || snapshot.metadata.hasPendingWrites) {
      throw StateError('private-data-server-proof-required');
    }
    if (!snapshot.exists) return const DedaPrivateDataRevision(0, null, null);
    final d = snapshot.data();
    const keys = {'format', 'accountKey', 'originalId', 'version', 'mutationId', 'payload', 'sourceUid', 'updatedAt'};
    if (d == null || d.length != keys.length || !keys.every(d.containsKey) ||
        d['format'] != 1 || d['accountKey'] != account || d['originalId'] != original ||
        d['version'] is! int || d['mutationId'] is! String || d['payload'] is! String ||
        d['sourceUid'] is! String || (d['sourceUid'] as String).isEmpty || d['updatedAt'] is! Timestamp) {
      throw const FormatException('invalid-server-private-data');
    }
    final result = DedaPrivateDataRevision(d['version'] as int, d['mutationId'] as String,
        DedaPrivateDataPayload.decode(d['payload'] as String));
    result.validate(); return result;
  }
  DocumentReference<Map<String, dynamic>> _ref(String account) =>
      FirebaseFirestore.instance.doc('deda_private_account_data/$account');
  @override
  Future<DedaPrivateDataRevision> readServer(String account, String original, void Function() check) async {
    check();
    final snap = await _ref(account).get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 12));
    check(); return _decode(snap, account, original);
  }
  @override
  Future<DedaPrivateDataRevision> compareAndSet(String account, String original,
      int baseVersion, String mutationId, DedaPrivateDataPayload payload, void Function() check) async {
    check(); final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('private-data-owner-required');
    final ref = _ref(account), history = _ref(account).collection('versions').doc(mutationId);
    // No outer timeout/retry of this write: keep the original Future and its
    // journal live until it settles; SDK transaction retries reread all inputs.
    final result = await FirebaseFirestore.instance.runTransaction<DedaPrivateDataRevision>((tx) async {
      check(); final snap = await tx.get(ref); check();
      final old = _decode(snap, account, original);
      if (old.mutationId == mutationId) {
        if (old.payload?.encode() != payload.encode()) throw const FormatException('private-data-mutation-conflict');
        return old;
      }
      if (old.version != baseVersion) throw const DedaPrivateDataConflict();
      final previous = await tx.get(history); check();
      if (previous.exists) throw const DedaPrivateDataConflict();
      if (FirebaseAuth.instance.currentUser?.uid != uid) throw const DedaPrivateDataStale();
      final next = DedaPrivateDataRevision(baseVersion + 1, mutationId, payload); next.validate();
      final data = <String, dynamic>{'format': 1, 'accountKey': account, 'originalId': original,
        'version': next.version, 'mutationId': mutationId, 'payload': payload.encode(),
        'sourceUid': uid, 'updatedAt': FieldValue.serverTimestamp()};
      tx.set(ref, data); tx.set(history, data); return next;
    });
    check(); return result;
  }
}

class _PrivateOwner {
  _PrivateOwner() : account = DedaBackend.accountKeyForPhone(DedaPreferences.phone),
      original = DedaBackend.personalShareIdForPhone(DedaPreferences.phone).trim(),
      epoch = DedaPreferences.stabilityAccountEpoch, principal = DedaAuthRuntime.capture();
  final String account, original;
  final int epoch;
  final DedaAuthSnapshot? principal;
  bool current() {
    try {
      DedaSectionOperationContext.checkCurrent();
      final live = DedaAuthRuntime.capture();
      return DedaPreferences.isLoggedIn && epoch == DedaPreferences.stabilityAccountEpoch &&
          account == DedaBackend.accountKeyForPhone(DedaPreferences.phone) &&
          principal != null && principal!.kind == DedaSessionAuthKind.anonymous &&
          live != null && principal!.matches(live);
    } catch (_) { return false; }
  }
  void check() { if (!current()) throw const DedaPrivateDataStale(); }
}

/// Original native records remain untouched. Restores are an atomic account-
/// scoped bundle; bound stores read/write it after adoption. A failed restore
/// cannot partially replace a native list or assign device data to a new user.
class DedaPrivateDataBridge {
  static final io = DedaFirebasePrivateDataIo();
  static final sync = DedaPrivateDataSync(io);
  static final changes = ValueNotifier<int>(0);
  static final Map<String, DedaPrivateDataStatus> statuses = {};
  static final Map<String, Future<void>> _localLanes = {};
  static final Set<String> _autoRestored = {};
  static String _bundleKey(String account) => 'deda_private_data_bundle_v1_$account';
  static String? _logical(String key, String account) {
    const global = {'deda_favorites_v1': 'favorites', 'deda_recent_v1': 'recent',
      'deda_personal_places_v1': 'personalPlaces', 'deda_contact_draft_v1': 'contactDraft'};
    if (global.containsKey(key)) return global[key];
    if (key == 'deda_traffic_quiz_seen_v1_$account') return 'quizSeen';
    for (final entry in {'daily_ids': 'ids', 'progress': 'progress', 'completed': 'completed'}.entries) {
      final prefix = 'deda_traffic_quiz_${entry.key}_v1_${account}_';
      if (key.startsWith(prefix)) {
        final result = 'quiz:${entry.value}:${key.substring(prefix.length)}';
        if (DedaPrivateDataPayload.validKey(result)) return result;
      }
    }
    throw ArgumentError('unsupported-private-native-key');
  }
  static DedaPrivateDataPayload? _bundle(SharedPreferences prefs, String account) {
    final raw = prefs.getString(_bundleKey(account));
    return raw == null ? null : DedaPrivateDataPayload.decode(raw);
  }
  static Future<Object?> read(SharedPreferences prefs, String key) async {
    if (!dedaPrivateDataEnabled || !DedaPreferences.isLoggedIn) return prefs.get(key);
    final owner = _PrivateOwner(); owner.check(); final account = owner.account;
    final field = _logical(key, account)!;
    var bundle = _bundle(prefs, account);
    final emptyDevice = const ['deda_favorites_v1', 'deda_recent_v1',
      'deda_personal_places_v1', 'deda_contact_draft_v1'].every((k) => !prefs.containsKey(k));
    final attempt = '$account/${owner.epoch}';
    if (bundle == null && emptyDevice && !_autoRestored.contains(attempt)) {
      // New handset only. Existing device-wide content needs explicit adoption.
      // Add the marker only after a successful verified read; failures can retry.
      final result = await restoreConfirmed(); owner.check();
      if (result.status == DedaPrivateDataStatus.saved || result.status == DedaPrivateDataStatus.absent) {
        _autoRestored.add(attempt);
      }
      bundle = _bundle(prefs, account);
    }
    owner.check();
    // Compatibility only: never upload/adopt device-wide records implicitly.
    return bundle == null ? prefs.get(key) : bundle.fields[field];
  }
  static Future<String?> readString(SharedPreferences prefs, String key) async => (await read(prefs, key)) as String?;
  static Future<List<String>?> readList(SharedPreferences prefs, String key) async {
    final value = await read(prefs, key);
    return value == null ? null : List<String>.from(value as List);
  }
  static Future<bool?> readBool(SharedPreferences prefs, String key) async => (await read(prefs, key)) as bool?;
  static Future<bool> write(SharedPreferences prefs, String key, Object? value) async {
    if (!dedaPrivateDataEnabled || !DedaPreferences.isLoggedIn) return _nativeWrite(prefs, key, value);
    final owner = _PrivateOwner(); owner.check(); final field = _logical(key, owner.account)!;
    final before = _localLanes[owner.account], done = Completer<void>(); _localLanes[owner.account] = done.future;
    try {
      if (before != null) await before; owner.check();
      final bundle = _bundle(prefs, owner.account);
      if (bundle == null) return await _nativeWrite(prefs, key, value);
      final next = DedaPrivateDataPayload({...bundle.fields, field: value});
      if (!await prefs.setString(_bundleKey(owner.account), next.encode())) return false;
      owner.check();
      // Native persistence is complete before returning. Background upload is
      // observed; later edits retain their own durable bundle if it fails.
      unawaited(_upload(owner, next).then<void>((_) {}, onError: (Object _, StackTrace __) {}));
      return true;
    } finally {
      done.complete(); if (identical(_localLanes[owner.account], done.future)) _localLanes.remove(owner.account);
    }
  }
  static Future<bool> _nativeWrite(SharedPreferences prefs, String key, Object? value) {
    if (value == null) return prefs.remove(key);
    if (value is String) return prefs.setString(key, value);
    if (value is bool) return prefs.setBool(key, value);
    if (value is List<String>) return prefs.setStringList(key, value);
    throw ArgumentError('unsupported-private-native-value');
  }
  static Future<DedaPrivateDataResult> _upload(_PrivateOwner owner, DedaPrivateDataPayload payload) async {
    final result = await sync.backup(account: owner.account, original: owner.original,
        payload: payload, isCurrent: owner.current);
    owner.check();
    final prefs = await SharedPreferences.getInstance(); owner.check();
    statuses[owner.account] = result.status == DedaPrivateDataStatus.saved &&
        _bundle(prefs, owner.account)?.encode() != payload.encode()
        ? DedaPrivateDataStatus.pending : result.status;
    changes.value++;
    return result;
  }
  static Future<DedaPrivateDataResult> backupConfirmed() async {
    if (!dedaPrivateDataEnabled || Firebase.apps.isEmpty) throw StateError('private-data-not-configured');
    final owner = _PrivateOwner(); owner.check();
    await io.verifyOwner(owner.account, owner.original, owner.check); owner.check();
    final prefs = await SharedPreferences.getInstance(); owner.check();
    var payload = _bundle(prefs, owner.account);
    if (payload == null) {
      final fields = <String, Object?>{};
      for (final key in ['deda_favorites_v1', 'deda_recent_v1', 'deda_personal_places_v1', 'deda_contact_draft_v1']) {
        fields[_logical(key, owner.account)!] = prefs.get(key);
      }
      final quizKeys = prefs.getKeys().where((key) =>
        key == 'deda_traffic_quiz_seen_v1_${owner.account}' ||
        ['daily_ids', 'progress', 'completed'].any((part) =>
          key.startsWith('deda_traffic_quiz_${part}_v1_${owner.account}_')));
      for (final key in quizKeys) { fields[_logical(key, owner.account)!] = prefs.get(key); }
      payload = DedaPrivateDataPayload(fields);
      owner.check();
      if (!await prefs.setString(_bundleKey(owner.account), payload.encode())) throw StateError('private-data-adoption-not-saved');
    }
    owner.check(); return _upload(owner, payload);
  }
  static Future<DedaPrivateDataResult> restoreConfirmed({bool discardPending = false}) async {
    if (!dedaPrivateDataEnabled || Firebase.apps.isEmpty) throw StateError('private-data-not-configured');
    final owner = _PrivateOwner(); owner.check();
    final beforePrefs = await SharedPreferences.getInstance(); owner.check();
    final beforeBundle = beforePrefs.getString(_bundleKey(owner.account));
    final result = await sync.restore(account: owner.account, original: owner.original,
        isCurrent: owner.current, discardPending: discardPending); owner.check();
    if (result.status == DedaPrivateDataStatus.saved) {
      final prefs = await SharedPreferences.getInstance(); owner.check();
      final old = prefs.getString(_bundleKey(owner.account));
      if (old != beforeBundle) {
        statuses[owner.account] = DedaPrivateDataStatus.conflict; changes.value++;
        return DedaPrivateDataResult(DedaPrivateDataStatus.conflict, result.revision);
      }
      if (old != null) { await io.preserveJournal(owner.account, old); owner.check(); }
      if (!await prefs.setString(_bundleKey(owner.account), result.revision.payload!.encode())) {
        throw StateError('private-data-restore-not-saved');
      }
      owner.check();
    }
    statuses[owner.account] = result.status; changes.value++; return result;
  }
}
