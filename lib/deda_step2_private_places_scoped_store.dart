import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'deda_100431_linked_owner_session_policy.dart';

/// Private source-only pilot. Do NOT read, claim, migrate or erase the legacy
/// global 'deda_personal_places_v1' key: it has no reliable account owner.
/// Does not back up to Firebase, create published places or restore a phone.
const bool dedaStep2PrivatePlacesScopedPilot = bool.fromEnvironment(
  'DEDA_STEP2_PRIVATE_PLACES_SCOPED_PILOT', defaultValue: false);

class DedaStep2PrivatePlacesHold implements Exception {
  const DedaStep2PrivatePlacesHold(this.reason);
  final String reason;
  @override
  String toString() => 'DedaStep2PrivatePlacesHold($reason)';
}

abstract class DedaStep2PrivatePlacesLocal {
  Future<String?> read(String key);
  Future<bool> write(String key, String value);
}

class DedaStep2PrivatePlacesPrefs implements DedaStep2PrivatePlacesLocal {
  const DedaStep2PrivatePlacesPrefs();
  @override
  Future<String?> read(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);
  @override
  Future<bool> write(String key, String value) async =>
      (await SharedPreferences.getInstance()).setString(key, value);
}

/// A private, account-scoped LOCAL source for newly entered private places.
/// The old unscoped array is intentionally not an input to this writer.
class DedaStep2PrivatePlacesScope {
  const DedaStep2PrivatePlacesScope({
    required this.local,
    required this.currentUid,
    required this.verifyOriginalOwner,
    this.enabled = dedaStep2PrivatePlacesScopedPilot,
  });

  factory DedaStep2PrivatePlacesScope.firebase() =>
      DedaStep2PrivatePlacesScope(
        local: const DedaStep2PrivatePlacesPrefs(),
        currentUid: () => FirebaseAuth.instance.currentUser?.uid,
        verifyOriginalOwner: (uid, key) async {
          final user = FirebaseAuth.instance.currentUser;
          return user != null && user.uid == uid &&
              await DedaLinkedOwnerSessionPolicy.verified(user, key);
        },
      );

  static const legacyGlobalKey = 'deda_personal_places_v1';
  final DedaStep2PrivatePlacesLocal local;
  final String? Function() currentUid;
  final Future<bool> Function(String uid, String accountKey)
      verifyOriginalOwner;
  final bool enabled;

  static String key(String accountKey, String originalUid) {
    if (!RegExp(r'^[0-9]{10,16}$').hasMatch(accountKey) ||
        !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(originalUid)) {
      throw const DedaStep2PrivatePlacesHold('private-place-account-scope-invalid');
    }
    return 'deda_step2_private_places_scoped_v1_${accountKey}_${originalUid}';
  }

  void _current(String uid, bool Function() isCurrent) {
    if (!enabled || currentUid() != uid || !isCurrent()) {
      throw const DedaStep2PrivatePlacesHold('private-place-owner-session-lost');
    }
  }

  static List<Map<String, dynamic>> _validate(Object? raw) {
    if (raw is! List || raw.length > 100) {
      throw const DedaStep2PrivatePlacesHold('private-place-list-invalid');
    }
    final seen = <String>{};
    final result = <Map<String, dynamic>>[];
    for (final item in raw) {
      if (item is! Map ||
          item.keys.toSet().difference({
            'id', 'name', 'note', 'latitude', 'longitude',
          }).isNotEmpty ||
          item.length != 5 ||
          item['id'] is! String ||
          item['name'] is! String ||
          item['note'] is! String ||
          item['latitude'] is! num ||
          item['longitude'] is! num) {
        throw const DedaStep2PrivatePlacesHold('private-place-entry-invalid');
      }
      final placeId = item['id'] as String;
      final name = item['name'] as String;
      final note = item['note'] as String;
      final latitude = (item['latitude'] as num).toDouble();
      final longitude = (item['longitude'] as num).toDouble();
      if (placeId.isEmpty || placeId.length > 80 ||
          placeId.contains('/') || !seen.add(placeId) ||
          name.trim().isEmpty || name.length > 160 ||
          note.length > 2048 || !latitude.isFinite ||
          !longitude.isFinite || latitude < -90 || latitude > 90 ||
          longitude < -180 || longitude > 180) {
        throw const DedaStep2PrivatePlacesHold('private-place-data-invalid');
      }
      result.add({
        'id': placeId, 'name': name, 'note': note,
        'latitude': latitude, 'longitude': longitude,
      });
    }
    return List.unmodifiable(result);
  }

  Future<void> _prove(String uid, String accountKey,
      bool Function() isCurrent) async {
    key(accountKey, uid);
    _current(uid, isCurrent);
    if (!await verifyOriginalOwner(uid, accountKey)) {
      throw const DedaStep2PrivatePlacesHold('private-place-owner-unverified');
    }
    _current(uid, isCurrent);
  }

  /// No legacy global read, not even for a currently logged-in owner.
  Future<List<Map<String, dynamic>>> readScoped({
    required String accountKey,
    required String originalUid,
    required bool Function() isCurrent,
  }) async {
    await _prove(originalUid, accountKey, isCurrent);
    final raw = await local.read(key(accountKey, originalUid));
    _current(originalUid, isCurrent);
    if (raw == null) return List.unmodifiable(<Map<String, dynamic>>[]);
    if (utf8.encode(raw).length > 262144) {
      throw const DedaStep2PrivatePlacesHold('private-place-source-too-large');
    }
    final dynamic object;
    try {
      object = jsonDecode(raw);
    } catch (_) {
      throw const DedaStep2PrivatePlacesHold('private-place-source-corrupt');
    }
    if (object is! Map || object.length != 4 ||
        object['format'] != 1 ||
        object['accountKey'] != accountKey ||
        object['originalUid'] != originalUid) {
      throw const DedaStep2PrivatePlacesHold('private-place-scope-conflict');
    }
    return _validate(object['places']);
  }

  /// Local scope-only write, not a migration. New entries can be maintained
  /// independently per verified account. Never overwrites the old global key.
  Future<void> saveScoped({
    required String accountKey,
    required String originalUid,
    required List<Map<String, dynamic>> places,
    required bool Function() isCurrent,
  }) async {
    await _prove(originalUid, accountKey, isCurrent);
    final checked = _validate(places);
    final name = key(accountKey, originalUid);
    final existing = await local.read(name);
    _current(originalUid, isCurrent);
    if (existing != null) {
      // Reject corrupt/foreign existing scoped data instead of overwriting it.
      await readScoped(accountKey: accountKey,
          originalUid: originalUid, isCurrent: isCurrent);
    }
    final encoded = jsonEncode({
      'format': 1, 'accountKey': accountKey,
      'originalUid': originalUid, 'places': checked,
    });
    if (utf8.encode(encoded).length > 262144) {
      throw const DedaStep2PrivatePlacesHold('private-place-source-too-large');
    }
    _current(originalUid, isCurrent);
    if (!await local.write(name, encoded)) {
      throw const DedaStep2PrivatePlacesHold('private-place-local-write-failed');
    }
    _current(originalUid, isCurrent);
    if (await local.read(name) != encoded) {
      throw const DedaStep2PrivatePlacesHold('private-place-local-readback-mismatch');
    }
    _current(originalUid, isCurrent);
  }
}
