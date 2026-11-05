import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'deda_step2_global_places_settings_archive.dart';
import 'deda_step2_local_places_settings_evidence.dart';

/// Stage 2 source-only migration. Never called on ordinary startup, and
/// never writes money, awards, purchase claims, IDs or server documents.
const bool dedaStep2GlobalPlacesSettingsRestoreEnabled = bool.fromEnvironment(
  'DEDA_STEP2_GLOBAL_PLACES_SETTINGS_RESTORE', defaultValue: false);

abstract class DedaStep2GlobalLocalRestoreIo {
  Future<Object?> read(String key);
  Future<bool> write(String key, Object value);
}

class DedaStep2GlobalPrefsRestoreIo implements DedaStep2GlobalLocalRestoreIo {
  const DedaStep2GlobalPrefsRestoreIo();
  @override
  Future<Object?> read(String key) async =>
      (await SharedPreferences.getInstance()).get(key);

  @override
  Future<bool> write(String key, Object value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is List<String>) return prefs.setStringList(key, value);
    if (value is String) return prefs.setString(key, value);
    if (value is bool) return prefs.setBool(key, value);
    if (value is int) return prefs.setInt(key, value);
    if (value is double) return prefs.setDouble(key, value);
    throw const DedaStep2GlobalPlacesHold(
        'replacement-preference-type-not-supported');
  }
}

/// Exactly one original-UID source, explicit recovery and a non-destructive
/// local merge. Device-global keys must not overwrite settings from an
/// existing user of the replacement phone.
class DedaStep2GlobalPlacesReplacementRestore {
  const DedaStep2GlobalPlacesReplacementRestore({
    required this.source,
    required this.local,
    required this.currentUid,
    this.enabled = dedaStep2GlobalPlacesSettingsRestoreEnabled,
  });

  factory DedaStep2GlobalPlacesReplacementRestore.firebase() =>
      DedaStep2GlobalPlacesReplacementRestore(
        source: DedaStep2GlobalPlacesArchive.firebaseCandidate(),
        local: const DedaStep2GlobalPrefsRestoreIo(),
        currentUid: () => FirebaseAuth.instance.currentUser?.uid,
      );

  final DedaStep2GlobalPlacesArchive source;
  final DedaStep2GlobalLocalRestoreIo local;
  final String? Function() currentUid;
  final bool enabled;

  static final Set<String> _active = <String>{};

  bool _same(Object? a, Object? b) {
    if (a is List && b is List) {
      return jsonEncode(a) == jsonEncode(b);
    }
    return a == b;
  }

  Future<bool> restoreExplicit({
    required String accountKey,
    required String originalId,
    required String originalUid,
    required bool Function() isCurrent,
  }) async {
    void check() {
      if (!enabled || !isCurrent() || currentUid() != originalUid) {
        throw const DedaStep2GlobalPlacesHold(
            'replacement-global-owner-session-changed');
      }
    }
    check();
    if (!_active.add(accountKey)) {
      throw const DedaStep2GlobalPlacesHold(
          'replacement-global-restore-already-running');
    }
    try {
      // Fresh remote source and original owner proof come from the
      // existing audited archive implementation. Never trust a local copy.
      final snapshot = await source.inspectReplacement(
        accountKey: accountKey, originalId: originalId,
        originalUid: originalUid, isCurrent: isCurrent,
      );
      check();
      final decoded = jsonDecode(snapshot.encoded) as Map;
      final records = decoded['records'] as Map;
      final keys = DedaStep2GlobalPlacesSnapshot.keys(accountKey);
      if (records.length != keys.length ||
          !keys.every(records.containsKey)) {
        throw const DedaStep2GlobalPlacesHold(
            'replacement-global-source-incomplete');
      }
      // Validate ALL source entries and detect ALL current-device conflicts
      // BEFORE any local write. Missing old values are never assumed zero.
      final absent = <String,Object>{};
      for (final key in keys) {
        check();
        final raw = records[key];
        if (raw == null) continue;
        if (DedaStep2LocalPlacesSettingsReader.inspectRawValue(key, raw) !=
            DedaStep2LocalSourceStatus.capturedUntrusted) {
          throw const DedaStep2GlobalPlacesHold(
              'replacement-global-source-invalid');
        }
        final current = await local.read(key);
        check();
        if (current != null && !_same(current, raw)) {
          throw const DedaStep2GlobalPlacesHold(
              'replacement-global-existing-values-preserved');
        }
        if (current == null) {
          absent[key] = raw is List ? List<String>.unmodifiable(raw.cast<String>()) : raw;
        }
      }
      // Write-if-missing. Partial process kills are idempotent: a retry
      // accepts exact prior values but never overwrites a conflicting one.
      for (final entry in absent.entries) {
        check();
        final now = await local.read(entry.key);
        check();
        if (now != null) {
          if (!_same(now, entry.value)) {
            throw const DedaStep2GlobalPlacesHold(
                'replacement-global-concurrent-local-change');
          }
          continue;
        }
        if (!await local.write(entry.key, entry.value)) {
          throw const DedaStep2GlobalPlacesHold(
              'replacement-global-preference-write-failed');
        }
        check();
        if (!_same(await local.read(entry.key), entry.value)) {
          throw const DedaStep2GlobalPlacesHold(
              'replacement-global-local-readback-failed');
        }
      }
      check();
      // Verify the exact source is still the same after all local writes.
      final again = await source.inspectReplacement(
        accountKey: accountKey, originalId: originalId,
        originalUid: originalUid, isCurrent: isCurrent,
      );
      check();
      if (again.encoded != snapshot.encoded) {
        throw const DedaStep2GlobalPlacesHold(
            'replacement-global-source-changed-mid-restore');
      }
      return records.values.any((item) => item != null);
    } finally {
      _active.remove(accountKey);
    }
  }
}
