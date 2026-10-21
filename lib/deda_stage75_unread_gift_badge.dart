import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'deda_stage71_free_manager_200_service.dart';
import 'deda_stage74_id_gift_service.dart';

/// Stage75: a LOCAL *viewed* marker for the new, verified identifier gift
/// inbox. It never acknowledges a gift, modifies its permanent owner, grants
/// identifiers, or touches existing diamond gift notifications.
/// The seen marker is scoped to BOTH verified auth UID and immutable original
/// account ID, so changing accounts cannot leak another account's badge.
class DedaStage75UnreadGiftBadge {
  DedaStage75UnreadGiftBadge._();

  static final ValueNotifier<int> pendingNotifier = ValueNotifier<int>(0);
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _listener;
  static StreamSubscription<User?>? _authListener;
  static String? _activeKey;
  static String? _activeUid;
  static int _generation = 0;

  static String _identity(String uid, String originalId) =>
      '$uid|$originalId';

  static String _seenPreference(String uid, String originalId) =>
      'deda_stage75_seen_id_gifts_${uid}_${originalId.replaceAll('@', '')}';

  static int unreadCount(Iterable<String> currentIds, Set<String> viewed) =>
      currentIds.toSet().difference(viewed).length;

  static bool _stillCurrent(int generation, String uid, String originalId) =>
      generation == _generation &&
      _activeKey == _identity(uid, originalId) &&
      FirebaseAuth.instance.currentUser?.uid == uid;

  static Future<void> start(String originalId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (!DedaStage74IdGiftService.enabled ||
        user == null ||
        !RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(originalId)) {
      await stop();
      return;
    }
    final uid = user.uid;
    final key = _identity(uid, originalId);
    if (_activeKey == key && _listener != null) return;
    final generation = ++_generation;
    _activeKey = key;
    _activeUid = uid;
    pendingNotifier.value = 0;
    await _listener?.cancel();
    _listener = null;
    _authListener ??= FirebaseAuth.instance.authStateChanges().listen((auth) {
      if (_activeUid != null && auth?.uid != _activeUid) {
        unawaited(stop());
      }
    });
    try {
      // load() proves same verified Firebase UID, users.accountKey,
      // deda_sessions.accountKey and original ID BEFORE displaying anything.
      final verified = await DedaStage74IdGiftService.load(originalId);
      if (!_stillCurrent(generation, uid, originalId)) return;
      await _showUnread(verified, generation, uid, originalId);
      if (!_stillCurrent(generation, uid, originalId)) return;
      _listener = FirebaseFirestore.instance
          .collection(DedaStage71Admin200.registry)
          .where('recipientOriginalId', isEqualTo: originalId)
          .snapshots()
          .listen((snapshot) {
        if (!snapshot.metadata.isFromCache) {
          unawaited(_refresh(generation, uid, originalId));
        }
      }, onError: (_) {
        // No badge count is fabricated during a network/security failure.
      });
    } catch (_) {
      // Do not show another account's unread count if verification fails.
      if (_stillCurrent(generation, uid, originalId)) {
        pendingNotifier.value = 0;
      }
    }
  }

  static Future<void> _refresh(
      int generation, String uid, String originalId) async {
    if (!_stillCurrent(generation, uid, originalId)) return;
    try {
      final verified = await DedaStage74IdGiftService.load(originalId);
      if (_stillCurrent(generation, uid, originalId)) {
        await _showUnread(verified, generation, uid, originalId);
      }
    } catch (_) {
      // Preserve the last verified count on a transient server failure.
    }
  }

  static Future<void> _showUnread(List<DedaStage74IdGift> gifts,
      int generation, String uid, String originalId) async {
    final prefs = await SharedPreferences.getInstance();
    if (!_stillCurrent(generation, uid, originalId)) return;
    final viewed = prefs.getStringList(_seenPreference(uid, originalId))
            ?.toSet() ??
        <String>{};
    // Claimed gifts are already in permanent history. On a new device a
    // missing LOCAL seen marker must never resurrect an old claimed gift.
    final ids = gifts
        .where((gift) => gift.originalId == originalId && !gift.received)
        .map((gift) => gift.identifier);
    pendingNotifier.value = unreadCount(ids, viewed);
  }

  /// Call ONLY after the verified gift inbox has successfully loaded and the
  /// cards are visible. Merely viewing is NOT the same as claiming a gift.
  static Future<void> markViewed(
      String originalId, List<DedaStage74IdGift> verifiedGifts) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _activeKey != _identity(uid, originalId) ||
        verifiedGifts.any((gift) => gift.originalId != originalId)) {
      return;
    }
    final generation = _generation;
    final prefs = await SharedPreferences.getInstance();
    if (!_stillCurrent(generation, uid, originalId)) return;
    final key = _seenPreference(uid, originalId);
    final seen = prefs.getStringList(key)?.toSet() ?? <String>{};
    seen.addAll(verifiedGifts.map((gift) => gift.identifier));
    final persisted = await prefs.setStringList(key, seen.toList()..sort());
    if (persisted && _stillCurrent(generation, uid, originalId)) {
      pendingNotifier.value = 0;
    }
  }

  static Future<void> stop() async {
    _generation++;
    _activeKey = null;
    _activeUid = null;
    pendingNotifier.value = 0;
    final previous = _listener;
    _listener = null;
    await previous?.cancel();
  }
}
