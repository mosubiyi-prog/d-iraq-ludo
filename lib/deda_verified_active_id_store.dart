import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Presentation-only, per-UID memory of the latest server-confirmed active ID.
/// It never authorizes an account, routes a share, owns a grant or writes to
/// Firebase. Cold-boot memory is optimistic UI and MUST be reconciled by the
/// ordinary owner-authenticated Stage71 server read.
class DedaVerifiedActiveId {
  const DedaVerifiedActiveId({
    required this.uid,
    required this.originalId,
    required this.displayId,
    required this.fixedColor,
  });

  final String uid;
  final String originalId;
  final String displayId;
  final String? fixedColor;

  bool get wellFormed =>
      uid.isNotEmpty &&
      RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(originalId) &&
      (displayId == originalId && fixedColor == null ||
          displayId != originalId &&
              RegExp(r'^@DEDA-[A-Z0-9]{4,12}$').hasMatch(displayId) &&
              const {'gold', 'diamond', 'royal', 'pink'}.contains(fixedColor));

  Map<String, String?> toJson() => {
    'uid': uid, 'originalId': originalId, 'displayId': displayId,
    'fixedColor': fixedColor,
  };

  static DedaVerifiedActiveId? fromJson(Object? input) {
    if (input is! Map<String, dynamic>) return null;
    final uid = input['uid'];
    final original = input['originalId'];
    final display = input['displayId'];
    final color = input['fixedColor'];
    if (uid is! String || original is! String || display is! String ||
        color != null && color is! String) return null;
    final result = DedaVerifiedActiveId(
      uid: uid, originalId: original, displayId: display,
      fixedColor: color as String?,
    );
    return result.wellFormed ? result : null;
  }
}

class DedaVerifiedActiveIdStore {
  DedaVerifiedActiveIdStore._();

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static final Map<(String, String), DedaVerifiedActiveId> _memory = {};
  static final Map<(String, String), Future<void>> _loading = {};

  static (String, String) _key(String uid, String originalId) =>
      (uid, originalId);

  static String _prefsKey(String uid, String originalId) {
    final encoded = base64Url.encode(utf8.encode('$uid|$originalId'));
    return 'deda_verified_active_display_v1_$encoded';
  }

  /// UI only: never use the returned value to validate ownership, send a
  /// location, spend a balance, execute a purchase or grant a permission.
  static DedaVerifiedActiveId? read(String uid, String originalId) {
    final value = _memory[_key(uid, originalId)];
    if (value == null || !value.wellFormed ||
        value.uid != uid || value.originalId != originalId) return null;
    return value;
  }

  /// Called ONLY by the verified Stage71 use/readback or the verified owner
  /// reader after checking the Firebase authenticated principal.
  static void confirmed({
    required String uid,
    required String originalId,
    required String displayId,
    required String? fixedColor,
  }) {
    final value = DedaVerifiedActiveId(
      uid: uid, originalId: originalId, displayId: displayId,
      fixedColor: fixedColor,
    );
    if (!value.wellFormed) throw StateError('invalid-verified-display-id');
    final key = _key(uid, originalId);
    final old = _memory[key];
    _memory[key] = value;
    if (old == null || old.displayId != displayId ||
        old.fixedColor != fixedColor) {
      revision.value += 1;
    }
    unawaited(_persist(key, value));
  }

  static Future<void> _persist(
      (String, String) key, DedaVerifiedActiveId value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // A second confirmed Use can overtake SharedPreferences initialization.
      // Never write an old verified ID after a newer local selection.
      if (!identical(_memory[key], value)) return;
      await prefs.setString(
        _prefsKey(value.uid, value.originalId), jsonEncode(value.toJson()));
    } catch (_) {
      // Cache availability must never block a verified server-side ID change.
    }
  }

  /// Non-blocking disk warm-up, scoped to the *current* Firebase UID and
  /// immutable canonical route. It does not generate an identity or trust a
  /// different account's stored data.
  static Future<void> restore(String uid, String originalId) {
    final key = _key(uid, originalId);
    if (_memory.containsKey(key)) return Future<void>.value();
    final pending = _loading[key];
    if (pending != null) return pending;
    final task = _restoreOnce(key);
    _loading[key] = task;
    task.whenComplete(() {
      if (identical(_loading[key], task)) _loading.remove(key);
    });
    return task;
  }

  static Future<void> _restoreOnce((String, String) key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey(key.$1, key.$2));
      if (raw == null || _memory.containsKey(key)) return;
      final saved = DedaVerifiedActiveId.fromJson(jsonDecode(raw));
      if (saved == null || saved.uid != key.$1 ||
          saved.originalId != key.$2 || _memory.containsKey(key)) return;
      _memory[key] = saved;
      revision.value += 1;
    } catch (_) {
      // No persistent cache means normal authenticated server loading.
    }
  }
}
