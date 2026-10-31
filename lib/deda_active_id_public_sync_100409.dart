import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'deda_qa32_spark_public_identifier_directory.dart';

/// Fire-and-forget PUBLIC DISPLAY projection only. Called solely after the
/// standard Stage71 owner reader has verified the ACTIVE ID and its genuine
/// owned/gifted registry receipt. This never changes the account routing ID,
/// balances, weekly scores, purchase records or the actual active selection.
///
/// The existing production Spark rules separately require same authenticated
/// account, matching Stage71 active selection, and a valid owned gift/color.
class DedaActiveIdPublicSync100409 {
  DedaActiveIdPublicSync100409._();
  static final Set<String> _pending = <String>{};
  static final Map<String, String> _success = <String, String>{};

  @visibleForTesting
  static bool shouldPublish({
    required String uid, required String originalId,
    required String activeId, required String? fixedColor,
    required String? currentUid,
  }) {
    return uid.isNotEmpty && currentUid == uid &&
        RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(originalId) &&
        activeId != originalId &&
        RegExp(r'^@DEDA-[A-Z0-9]{4,12}$').hasMatch(activeId) &&
        const {'gold', 'diamond', 'royal', 'pink'}.contains(fixedColor);
  }

  static Future<void> publishAfterVerifiedRead({
    required String uid,
    required String originalId,
    required String activeId,
    required String? fixedColor,
  }) async {
    if (!DedaQa32SparkPublicIdentifierDirectory.enabled ||
        !shouldPublish(
          uid: uid, originalId: originalId, activeId: activeId,
          fixedColor: fixedColor,
          currentUid: FirebaseAuth.instance.currentUser?.uid,
        )) return;
    final key = '$uid|$originalId';
    final value = '$activeId|$fixedColor';
    if (_pending.contains(key) || _success[key] == value) return;
    _pending.add(key);
    try {
      // Avoid network writes if this server-confirmed public projection
      // already matches the owner's genuine active selection.
      final existing = await FirebaseFirestore.instance
          .collection('deda_public_active_aliases').doc(originalId)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 5));
      if (FirebaseAuth.instance.currentUser?.uid != uid) return;
      final proof =
          DedaQa32SparkPublicIdentifierDirectory.styleFromProjection(
              originalId, existing.data());
      if (proof?['displayId'] != activeId ||
          proof?['permanentColor'] != fixedColor) {
        await DedaQa32SparkPublicIdentifierDirectory.publishOwnerVerified(
          originalId: originalId,
          selectedAlias: activeId,
          permanentColor: fixedColor,
        ).timeout(const Duration(seconds: 8));
      }
      if (FirebaseAuth.instance.currentUser?.uid == uid) {
        _success[key] = value;
      }
    } catch (error) {
      // Never delay/hide a verified owner ID because optional public
      // projection is offline or Firestore denies publication. A next
      // authenticated Stage71 read can retry.
      debugPrint('DEDA active ID public projection deferred: ${error.runtimeType}');
    } finally {
      _pending.remove(key);
    }
  }
}
