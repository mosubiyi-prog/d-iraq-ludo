import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Public-display-only compatibility with legacy Play 100340 users.
///
/// Current live rules DO NOT grant other accounts Stage71 GET. This is
/// DISABLED unless the separately audited authenticated read-only rules
/// change has actually been approved and deployed. No writes or API calls
/// are made while disabled.
///
/// The active Stage71 selection is definitive. The public alias projection
/// may be missing or delayed for old clients. Never assume "missing index"
/// means "normal ID", since the member may have selected a premium ID.
class DedaLegacy340ActiveSelection100418 {
  DedaLegacy340ActiveSelection100418._();

  static const bool enabled = bool.fromEnvironment(
    'DEDA_100418_LEGACY340_ACTIVE_READ_APPROVED',
    defaultValue: false,
  );
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static final RegExp _original = RegExp(r'^@DEDA-[A-Z0-9]{6}$');
  static final RegExp _display = RegExp(r'^@DEDA-[A-Z0-9]{4,12}$');

  static bool verifiedRoute(String original, Map<String, dynamic>? route) =>
      _original.hasMatch(original) &&
      route != null &&
      route['publicId'] == original &&
      route['kind'] == 'personal' &&
      route['active'] == true &&
      route['ownerUid'] is String &&
      (route['ownerUid'] as String).isNotEmpty;

  /// Called ONLY on an actual non-cache server Stage71 snapshot.
  /// Null is definitive NORMAL only if the associated public share route was
  /// independently read from SERVER and confirmed by verifiedRoute().
  @visibleForTesting
  static String? verifiedSelection({
    required String original,
    required Map<String, dynamic>? route,
    required Map<String, dynamic>? active,
  }) {
    if (!verifiedRoute(original, route)) return null;
    if (active == null) return original;
    if (active.length != 3 ||
        active['originalId'] != original ||
        active['updatedAt'] == null) return null;
    final id = active['activeId'];
    if (id is! String || !_display.hasMatch(id)) return null;
    return id;
  }

  static final Map<(String, String), int> _users = {};
  static final Map<(String, String),
      StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>> _streams = {};
  static final Map<(String, String), Timer> _timeouts = {};
  static final Map<(String, String), String> _confirmed = {};
  static final Map<(String, String), Map<String, dynamic>> _routes = {};
  static final Map<(String, String), Map<String, dynamic>?> _active = {};
  static final Set<(String, String)> _received = {};
  static final Set<(String, String)> _failed = {};

  static String? _uid() {
    if (Firebase.apps.isEmpty) return null;
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  static String? selected(String original) {
    if (!enabled) return null;
    final uid = _uid();
    if (uid == null || !_original.hasMatch(original)) return null;
    return _confirmed[(uid, original)];
  }

  static bool failed(String original) {
    if (!enabled) return false;
    final uid = _uid();
    return uid != null && _failed.contains((uid, original));
  }

  static void _notify() => revision.value++;

  static void _fail((String, String) key, Object error) {
    if (_uid() != key.$1 || !_users.containsKey(key)) return;
    final wasVisible = _confirmed.remove(key) != null;
    final markedFailed = _failed.add(key);
    final changed = wasVisible || markedFailed;
    if (error is FirebaseException) {
      debugPrint('DEDA 100418 active read error: ${error.code}');
    } else {
      debugPrint('DEDA 100418 active read error: ${error.runtimeType}');
    }
    if (changed) _notify();
  }

  static void _commit((String, String) key) {
    if (!_users.containsKey(key) || _uid() != key.$1 ||
        !_routes.containsKey(key) || !_received.contains(key)) return;
    final selected = verifiedSelection(
      original: key.$2, route: _routes[key], active: _active[key]);
    if (selected == null) {
      _fail(key, StateError('unverified-legacy-active'));
      return;
    }
    _timeouts.remove(key)?.cancel();
    final changedId = _confirmed[key] != selected;
    final recovered = _failed.remove(key);
    final change = changedId || recovered;
    _confirmed[key] = selected;
    if (change) _notify();
  }

  static void _start((String, String) key) {
    final uid = key.$1;
    final original = key.$2;
    if (_uid() != uid) return;
    final db = FirebaseFirestore.instance;
    _timeouts[key] = Timer(const Duration(seconds: 10), () {
      if (!_confirmed.containsKey(key)) {
        _fail(key, TimeoutException('legacy-id-server-confirmation'));
      }
    });

    // Single server route check per visible ID. Never read another account's
    // user document, private registry, wallet, session, grant or phone.
    unawaited(db.collection('deda_share_ids').doc(original)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 10))
        .then((snap) {
          if (_uid() != uid || !_users.containsKey(key)) return;
          final data = snap.data();
          if (!verifiedRoute(original, data)) {
            _fail(key, StateError('invalid-public-route'));
            return;
          }
          _routes[key] = data!;
          _commit(key);
        }).catchError((Object error) { _fail(key, error); }));

    // Live active source is authoritative. Never use from-cache selection or
    // pending local changes as public owner proof. A server-confirmed missing
    // document means normal only when public route was verified too.
    _streams[key] = db.collection('deda_stage71_active_identifier')
        .doc(original).snapshots(includeMetadataChanges: true)
        .listen((snap) {
          if (_uid() != uid || !_users.containsKey(key) ||
              snap.metadata.isFromCache ||
              snap.metadata.hasPendingWrites) return;
          _active[key] = snap.data();
          _received.add(key);
          _commit(key);
        }, onError: (Object error) { _fail(key, error); });
  }

  /// One shared listener per (authenticated viewer UID, original ID).
  static void Function() watch(String original) {
    if (!enabled || !_original.hasMatch(original)) return () {};
    final uid = _uid();
    if (uid == null) return () {};
    final key = (uid, original);
    final old = _users[key] ?? 0;
    _users[key] = old + 1;
    if (old == 0) _start(key);
    bool released = false;
    return () {
      if (released) return;
      released = true;
      final n = (_users[key] ?? 1) - 1;
      if (n > 0) {
        _users[key] = n;
        return;
      }
      _users.remove(key);
      _timeouts.remove(key)?.cancel();
      final sub = _streams.remove(key);
      if (sub != null) unawaited(sub.cancel());
      final wasVisible = _confirmed.remove(key) != null;
      _routes.remove(key);
      _active.remove(key);
      _received.remove(key);
      _failed.remove(key);
      if (wasVisible && _uid() == uid) _notify();
    };
  }
}
