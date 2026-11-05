import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'deda_step2_local_places_settings_evidence.dart';

/// Candidate only; NOT connected to main.dart, Firebase production or Play.
/// Device-global saved places may belong to another account on a shared phone.
const bool dedaStep2GlobalPlacesSettingsArchiveEnabled =
    bool.fromEnvironment('DEDA_STEP2_GLOBAL_PLACES_SETTINGS_ARCHIVE',
        defaultValue: false);

class DedaStep2GlobalPlacesHold implements Exception {
  const DedaStep2GlobalPlacesHold(this.reason);
  final String reason;
  @override
  String toString() => 'DedaStep2GlobalPlacesHold($reason)';
}

/// One immutable, account-bound old-phone source snapshot. Every entry is
/// untrusted display state, NOT user ownership or a monetary claim.
class DedaStep2GlobalPlacesSnapshot {
  const DedaStep2GlobalPlacesSnapshot._(
      this.accountKey, this.originalId, this.originalUid,
      this.captureId, this.encoded);

  final String accountKey, originalId, originalUid, captureId, encoded;

  static final RegExp _account = RegExp(r'^[0-9]{10,16}$');
  static final RegExp _id = RegExp(r'^@DEDA-[A-Z0-9]{6}$');
  static final RegExp _capture = RegExp(r'^[a-f0-9]{48}$');

  static List<String> keys(String account) => List<String>.unmodifiable([
    ...DedaStep2LocalPlacesSettingsReader.globalPlacesAndSettings,
    DedaStep2LocalPlacesSettingsReader.profileFreeFrameKey(account),
  ]);

  static bool _supported(String key, Object? value) {
    if (value == null) return true;
    if (key == 'deda_favorites_v1' || key == 'deda_recent_v1') {
      return value is List && value.every((item) => item is String);
    }
    if (key == 'deda_voice_enabled_v1') return value is bool;
    if (key == 'deda_speech_rate_v1') {
      return value is num && value.isFinite;
    }
    if (key.startsWith('deda_profile_frame_v1_')) return value is int;
    return value is String;
  }

  static DedaStep2GlobalPlacesSnapshot _decode(
      String encoded, String account, String original, String uid,
      String captureId) {
    if (!_account.hasMatch(account) || !_id.hasMatch(original) ||
        uid.trim().isEmpty || !_capture.hasMatch(captureId) ||
        utf8.encode(encoded).length > 650000) {
      throw const DedaStep2GlobalPlacesHold('invalid-global-source-identity');
    }
    final Object? object;
    try {
      object = jsonDecode(encoded);
    } on FormatException {
      throw const DedaStep2GlobalPlacesHold('malformed-global-source');
    }
    if (object is! Map || object.length != 8 ||
        object['format'] != 1 ||
        object['kind'] != 'untrusted-device-global-display-evidence' ||
        object['accountKey'] != account || object['originalId'] != original ||
        object['sourceUid'] != uid || object['captureId'] != captureId ||
        object['ownerConfirmedAtOriginalPhone'] != true ||
        object['records'] is! Map) {
      throw const DedaStep2GlobalPlacesHold('global-source-scope-conflict');
    }
    final records = object['records'] as Map;
    final expectedKeys = keys(account);
    if (records.length != expectedKeys.length ||
        !expectedKeys.every(records.containsKey) ||
        !expectedKeys.every((key) => _supported(key, records[key])) ||
        !records.values.any((v) => v != null)) {
      throw const DedaStep2GlobalPlacesHold('global-source-records-incomplete');
    }
    // Re-encoding enforces a unique immutable representation for retries.
    // The source bytes INSIDE String fields are left untouched.
    final normalized = <String,Object?>{
      'format':1,
      'kind':'untrusted-device-global-display-evidence',
      'accountKey':account,
      'originalId':original,
      'sourceUid':uid,
      'captureId':captureId,
      'ownerConfirmedAtOriginalPhone':true,
      'records':{for(final key in expectedKeys) key:records[key]},
    };
    if (jsonEncode(normalized) != encoded) {
      throw const DedaStep2GlobalPlacesHold('noncanonical-global-source');
    }
    return DedaStep2GlobalPlacesSnapshot._(
        account,original,uid,captureId,encoded);
  }

  static DedaStep2GlobalPlacesSnapshot fromOriginal({
    required DedaStep2LocalPlacesSettingsEvidence captured,
    required String originalUid,
    required String captureId,
    required bool explicitlyConfirmDeviceGlobalDataBelongsToAccount,
  }) {
    if (!explicitlyConfirmDeviceGlobalDataBelongsToAccount ||
        !captured.hasAnySource) {
      throw const DedaStep2GlobalPlacesHold(
          'global-source-account-attribution-not-approved');
    }
    final keysForAccount = keys(captured.accountKey);
    if (captured.values.length != keysForAccount.length ||
        !keysForAccount.every(captured.values.containsKey)) {
      throw const DedaStep2GlobalPlacesHold('global-source-capture-incomplete');
    }
    final encoded = jsonEncode(<String,Object?>{
      'format':1,
      'kind':'untrusted-device-global-display-evidence',
      'accountKey':captured.accountKey,
      'originalId':captured.originalId,
      'sourceUid':originalUid,
      'captureId':captureId,
      'ownerConfirmedAtOriginalPhone':true,
      'records':{for(final key in keysForAccount) key:captured.values[key]},
    });
    return _decode(encoded,captured.accountKey,captured.originalId,
        originalUid,captureId);
  }

  static DedaStep2GlobalPlacesSnapshot fromRecorded({
    required String encoded,
    required String accountKey,
    required String originalId,
    required String originalUid,
    required String captureId,
  }) => _decode(encoded,accountKey,originalId,originalUid,captureId);

  bool get canAutoImportIntoAnotherDevice => false;
  bool get canRewriteCurrentSavedPlaces => false;
  bool get fullAccountRestored => false;
  bool get mayEraseOriginalPhone => false;
}

class DedaStep2GlobalPlaceCloudRow {
  const DedaStep2GlobalPlaceCloudRow(this.data,
      {this.cached=false,this.pendingWrites=false});
  final Map<String,dynamic>? data;
  final bool cached,pendingWrites;
}

abstract class DedaStep2GlobalPlaceCloudIo {
  Future<DedaStep2GlobalPlaceCloudRow> read(String accountKey);
  /// Must atomically CREATE only when absent. Never overwrite an old source.
  Future<void> createOnce(String accountKey, Map<String,dynamic> body);
}

class DedaStep2GlobalPlaceFirestoreIo implements DedaStep2GlobalPlaceCloudIo {
  const DedaStep2GlobalPlaceFirestoreIo();
  DocumentReference<Map<String,dynamic>> _ref(String account) =>
    FirebaseFirestore.instance.collection('deda_step2_global_place_archives')
        .doc(account);

  @override
  Future<DedaStep2GlobalPlaceCloudRow> read(String accountKey) async {
    final row=await _ref(accountKey).get(
        const GetOptions(source:Source.server));
    return DedaStep2GlobalPlaceCloudRow(row.data(),
      cached:row.metadata.isFromCache,
      pendingWrites:row.metadata.hasPendingWrites);
  }

  @override
  Future<void> createOnce(String accountKey, Map<String,dynamic> body) async {
    await FirebaseFirestore.instance.runTransaction<void>((tx) async {
      final ref=_ref(accountKey);
      final before=await tx.get(ref);
      if (before.exists) {
        final existing=before.data();
        if (existing == null || existing.length != body.length+1 ||
            !body.keys.every((key) => existing[key] == body[key]) ||
            existing['createdAt'] is! Timestamp) {
          throw const DedaStep2GlobalPlacesHold(
            'immutable-global-place-snapshot-conflict');
        }
        return;
      }
      tx.set(ref,{...body,'createdAt':FieldValue.serverTimestamp()});
    });
  }
}

abstract class DedaStep2GlobalPlacesPendingJournal {
  Future<String?> read(String accountKey);
  Future<void> writeOnce(String accountKey, String encoded);
  Future<bool> clearIfSame(String accountKey, String encoded);
}

class DedaStep2GlobalPlacesPrefsJournal
    implements DedaStep2GlobalPlacesPendingJournal {
  const DedaStep2GlobalPlacesPrefsJournal();
  static final Set<String> _active = <String>{};
  String _key(String account) {
    if (!RegExp(r'^[0-9]{10,16}$').hasMatch(account)) {
      throw const DedaStep2GlobalPlacesHold('invalid-global-journal-account');
    }
    return 'deda_step2_global_places_pending_v1_' + account;
  }
  @override
  Future<String?> read(String accountKey) async =>
      (await SharedPreferences.getInstance()).getString(_key(accountKey));

  @override
  Future<void> writeOnce(String accountKey, String encoded) async {
    final key=_key(accountKey);
    if (!_active.add(key)) {
      throw const DedaStep2GlobalPlacesHold('global-journal-busy');
    }
    try {
      final prefs=await SharedPreferences.getInstance();
      final before=prefs.getString(key);
      if (before != null && before != encoded) {
        throw const DedaStep2GlobalPlacesHold(
          'global-journal-existing-pending-source');
      }
      if (before == null && !await prefs.setString(key,encoded)) {
        throw const DedaStep2GlobalPlacesHold('global-journal-not-saved');
      }
      if (prefs.getString(key) != encoded) {
        throw const DedaStep2GlobalPlacesHold('global-journal-readback-failed');
      }
    } finally {_active.remove(key);}
  }

  @override
  Future<bool> clearIfSame(String accountKey, String encoded) async {
    final key=_key(accountKey);
    if (!_active.add(key)) {
      throw const DedaStep2GlobalPlacesHold('global-journal-busy');
    }
    try {
      final prefs=await SharedPreferences.getInstance();
      if (prefs.getString(key) != encoded) return false;
      if (!await prefs.remove(key)) return false;
      return prefs.getString(key) == null;
    } finally {_active.remove(key);}
  }
}

/// Old-phone explicit backup, or new-phone readback. Both require the
/// independently proven SAME original UID. Offline/unknown must not create.
class DedaStep2GlobalPlacesArchive {
  const DedaStep2GlobalPlacesArchive({
    required this.reader,required this.cloud,required this.journal,
    required this.currentUid,required this.proveOwner,
    this.enabled = dedaStep2GlobalPlacesSettingsArchiveEnabled,
  });
  final DedaStep2LocalPlacesSettingsReader reader;
  final DedaStep2GlobalPlaceCloudIo cloud;
  final DedaStep2GlobalPlacesPendingJournal journal;
  final String? Function() currentUid;
  final Future<bool> Function(String uid,String account,String originalId)
      proveOwner;
  final bool enabled;

  void _check(String account,String originalId,String uid,
      bool Function() current) {
    if (!enabled || !current() || currentUid()!=uid ||
        uid.trim().isEmpty ||
        !RegExp(r'^[0-9]{10,16}$').hasMatch(account) ||
        !RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(originalId)) {
      throw const DedaStep2GlobalPlacesHold('global-original-owner-required');
    }
  }
  Future<void> _owner(String account,String originalId,String uid,
      bool Function() current) async {
    _check(account,originalId,uid,current);
    if (!await proveOwner(uid,account,originalId)) {
      throw const DedaStep2GlobalPlacesHold('global-owner-not-proven');
    }
    _check(account,originalId,uid,current);
  }

  static String newCaptureId() {
    final rng=Random.secure();
    return List.generate(24,(_)=>rng.nextInt(256))
      .map((v)=>v.toRadixString(16).padLeft(2,'0')).join();
  }

  /// Old device: create a durable local intent BEFORE any network write.
  /// Global prefs require explicit consent to attribute to this account.
  Future<DedaStep2GlobalPlacesSnapshot> prepareOriginal({
    required String accountKey,required String originalId,
    required String originalUid,required bool Function() isCurrent,
    required bool explicitlyConfirmDeviceGlobalDataBelongsToAccount,
  }) async {
    await _owner(accountKey,originalId,originalUid,isCurrent);
    final old=await journal.read(accountKey);
    _check(accountKey,originalId,originalUid,isCurrent);
    if (old != null) {
      final parsed=jsonDecode(old);
      if (parsed is! Map || parsed['captureId'] is! String) {
        throw const DedaStep2GlobalPlacesHold('global-pending-damaged');
      }
      return DedaStep2GlobalPlacesSnapshot.fromRecorded(
        encoded:old,accountKey:accountKey,originalId:originalId,
        originalUid:originalUid,captureId:parsed['captureId'] as String);
    }
    if (!explicitlyConfirmDeviceGlobalDataBelongsToAccount) {
      throw const DedaStep2GlobalPlacesHold(
        'original-phone-global-data-attribution-required');
    }
    final captured=await reader.inspectOriginalPhone(
      accountKey:accountKey,originalId:originalId,isCurrent:isCurrent);
    await _owner(accountKey,originalId,originalUid,isCurrent);
    final prepared=DedaStep2GlobalPlacesSnapshot.fromOriginal(
      captured:captured,originalUid:originalUid,
      captureId:newCaptureId(),
      explicitlyConfirmDeviceGlobalDataBelongsToAccount:true);
    await journal.writeOnce(accountKey,prepared.encoded);
    _check(accountKey,originalId,originalUid,isCurrent);
    if (await journal.read(accountKey) != prepared.encoded) {
      throw const DedaStep2GlobalPlacesHold('global-journal-not-durable');
    }
    return prepared;
  }

  Map<String,dynamic> _body(DedaStep2GlobalPlacesSnapshot snapshot) =>
      <String,dynamic>{
        'format':1,
        'kind':'untrusted-device-global-display-evidence',
        'accountKey':snapshot.accountKey,
        'originalId':snapshot.originalId,
        'sourceUid':snapshot.originalUid,
        'captureId':snapshot.captureId,
        'encoded':snapshot.encoded,
      };

  DedaStep2GlobalPlacesSnapshot _verifyCloud(
      DedaStep2GlobalPlaceCloudRow row,
      String account,String originalId,String uid) {
    final data=row.data;
    if (row.cached || row.pendingWrites || data == null ||
        data.length != 8 || data['createdAt'] is! Timestamp ||
        data['format'] != 1 ||
        data['kind'] != 'untrusted-device-global-display-evidence' ||
        data['accountKey'] != account ||
        data['sourceUid'] != uid ||
        data['originalId'] != originalId ||
        data['captureId'] is! String || data['encoded'] is! String) {
      throw const DedaStep2GlobalPlacesHold('global-snapshot-not-server-proven');
    }
    return DedaStep2GlobalPlacesSnapshot.fromRecorded(
      encoded:data['encoded'] as String, accountKey:account,
      originalId:originalId, originalUid:uid,
      captureId:data['captureId'] as String);
  }

  /// Retry-safe, only exact same frozen intent. Never rewrites source keys.
  Future<DedaStep2GlobalPlacesSnapshot> uploadPendingOriginal({
    required String accountKey,required String originalId,
    required String originalUid,required bool Function() isCurrent,
  }) async {
    await _owner(accountKey,originalId,originalUid,isCurrent);
    final pending=await journal.read(accountKey);
    _check(accountKey,originalId,originalUid,isCurrent);
    if (pending == null) {
      throw const DedaStep2GlobalPlacesHold('global-pending-intent-absent');
    }
    final parsed=jsonDecode(pending);
    if (parsed is! Map || parsed['captureId'] is! String) {
      throw const DedaStep2GlobalPlacesHold('global-pending-damaged');
    }
    final source=DedaStep2GlobalPlacesSnapshot.fromRecorded(
      encoded:pending,accountKey:accountKey,originalId:originalId,
      originalUid:originalUid,captureId:parsed['captureId'] as String);
    final before=await cloud.read(accountKey);
    _check(accountKey,originalId,originalUid,isCurrent);
    if (before.cached || before.pendingWrites) {
      throw const DedaStep2GlobalPlacesHold('global-cloud-uncertain');
    }
    if (before.data == null) {
      await cloud.createOnce(accountKey,_body(source));
      _check(accountKey,originalId,originalUid,isCurrent);
    }
    final confirmed=_verifyCloud(await cloud.read(accountKey),
      accountKey,originalId,originalUid);
    _check(accountKey,originalId,originalUid,isCurrent);
    if (confirmed.encoded != pending) {
      throw const DedaStep2GlobalPlacesHold(
        'global-source-different-from-pending');
    }
    if (!await journal.clearIfSame(accountKey,pending)) {
      throw const DedaStep2GlobalPlacesHold('global-journal-remains-uncertain');
    }
    _check(accountKey,originalId,originalUid,isCurrent);
    return confirmed;
  }

  /// New phone: same verified original UID, server-only, and NO local writes.
  Future<DedaStep2GlobalPlacesSnapshot> inspectReplacement({
    required String accountKey,required String originalId,
    required String originalUid,required bool Function() isCurrent,
  }) async {
    await _owner(accountKey,originalId,originalUid,isCurrent);
    final record=await cloud.read(accountKey);
    _check(accountKey,originalId,originalUid,isCurrent);
    final parsed=_verifyCloud(record,accountKey,originalId,originalUid);
    await _owner(accountKey,originalId,originalUid,isCurrent);
    return parsed;
  }
}
