import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'deda_active_id_public_sync_100409.dart';
import 'deda_qa32_spark_public_identifier_directory.dart';

/// Owner-only, verified legacy normal-ID repair. The stable ID never changes.
/// Only the currently signed-in UID's users.sharePersonalId and a missing
/// normal active-selection may be filled. Never write friends' documents,
/// wallet, gifts, scores, admin permissions or an existing premium selection.
///
/// If a legacy route belongs to a different UID, fail closed rather than
/// claiming someone else's ID. Such cases need independently audited rules.
class DedaOwnerLegacyPublicProof100414 {
  DedaOwnerLegacyPublicProof100414._();

  static final Set<String> _inFlight = {};
  static final Set<String> _completed = {};

  static bool sameAuthenticatedOwner({
    required String expectedUid,
    required String originalId,
    required Map<String, dynamic> user,
    required Map<String, dynamic> session,
    required Map<String, dynamic> route,
  }) {
    final key = user['accountKey'];
    return RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(originalId) &&
        expectedUid.isNotEmpty &&
        key is String && key.isNotEmpty &&
        session['accountKey'] == key &&
        route['publicId'] == originalId &&
        route['kind'] == 'personal' &&
        route['active'] == true &&
        route['ownerUid'] == expectedUid &&
        (user['sharePersonalId'] == null ||
            user['sharePersonalId'] == '' ||
            user['sharePersonalId'] == originalId);
  }

  static bool activeSelectionSafe({
    required String originalId,
    required String expectedActiveId,
    required Map<String, dynamic>? selection,
  }) {
    if (selection == null) return expectedActiveId == originalId;
    return selection['originalId'] == originalId &&
        selection['activeId'] == expectedActiveId;
  }

  /// Called asynchronously ONLY after Stage71 confirmed exact server owner,
  /// actual active ID and any premium receipt/color; UI does not await it.
  /// Two server-authorized transactions, not one. LIVE Stage71 Firestore
  /// rules require users.sharePersonalId already committed BEFORE an owner
  /// may even READ the active-selection document. A 100414 transaction that
  /// reads activeRef before setting the missing share ID is denied.
  ///
  /// No rules change, owner migration or guessing is necessary for a
  /// legitimately authenticated original account with a matching route.
  static Future<void> ensureAndPublish({
    required String uid,
    required String originalId,
    required String activeId,
    required String? fixedColor,
  }) async {
    if (!DedaQa32SparkPublicIdentifierDirectory.enabled ||
        !DedaActiveIdPublicSync100409.shouldPublish(
          uid: uid, originalId: originalId, activeId: activeId,
          fixedColor: fixedColor,
          currentUid: FirebaseAuth.instance.currentUser?.uid,
        )) return;
    final key = '$uid|$originalId|$activeId|$fixedColor';
    if (_inFlight.contains(key) || _completed.contains(key)) return;
    _inFlight.add(key);
    try {
      final db = FirebaseFirestore.instance;
      final userRef = db.collection('users').doc(uid);
      final sessionRef = db.collection('deda_sessions').doc(uid);
      final routeRef = db.collection('deda_share_ids').doc(originalId);
      final activeRef = db.collection('deda_stage71_active_identifier')
          .doc(originalId);

      // PHASE ONE. Only read public owner proof/user/session/route. Never
      // attempt a Stage71 read until this missing field is server-committed.
      // A separate authenticated session's UID cannot fill this owner's ID.
      await db.runTransaction((tx) async {
        final user = (await tx.get(userRef)).data() ?? <String,dynamic>{};
        final session = (await tx.get(sessionRef)).data() ?? <String,dynamic>{};
        final route = (await tx.get(routeRef)).data() ?? <String,dynamic>{};
        if (FirebaseAuth.instance.currentUser?.uid != uid ||
            !sameAuthenticatedOwner(
              expectedUid: uid, originalId: originalId,
              user: user, session: session, route: route)) {
          throw StateError('legacy-public-proof-not-authorized');
        }
        if (user['sharePersonalId'] != originalId) {
          tx.update(userRef, {'sharePersonalId': originalId});
        }
      }).timeout(const Duration(seconds: 12));
      if (FirebaseAuth.instance.currentUser?.uid != uid) return;

      // PHASE TWO. Now Stage71 rules permit reading the verified selection.
      // Recheck ownership after phase one and NEVER overwrite an existing
      // normal/premium selection, including one changed on another device.
      await db.runTransaction((tx) async {
        final user = (await tx.get(userRef)).data() ?? <String,dynamic>{};
        final session = (await tx.get(sessionRef)).data() ?? <String,dynamic>{};
        final route = (await tx.get(routeRef)).data() ?? <String,dynamic>{};
        final active = (await tx.get(activeRef)).data();
        if (FirebaseAuth.instance.currentUser?.uid != uid ||
            !sameAuthenticatedOwner(
              expectedUid: uid, originalId: originalId,
              user: user, session: session, route: route) ||
            !activeSelectionSafe(
              originalId: originalId, expectedActiveId: activeId,
              selection: active)) {
          throw StateError('legacy-active-selection-changed');
        }
        if (active == null) {
          // No missing normal row is created if any premium is selected.
          if (activeId != originalId) {
            throw StateError('premium-active-source-missing');
          }
          tx.set(activeRef, {
            'originalId': originalId,
            'activeId': originalId,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }).timeout(const Duration(seconds: 12));
      if (FirebaseAuth.instance.currentUser?.uid != uid) return;

      // The 100409 publisher intentionally swallows network errors. Do not
      // treat its Future returning as proof that Firebase accepted the write.
      await DedaActiveIdPublicSync100409.publishAfterVerifiedRead(
        uid: uid, originalId: originalId, activeId: activeId,
        fixedColor: fixedColor,
      );
      if (FirebaseAuth.instance.currentUser?.uid != uid) return;
      final published = await db.collection('deda_public_active_aliases')
          .doc(originalId).get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 12));
      final projection = published.data();
      if (!published.exists || projection == null ||
          projection.length != 4 ||
          projection['originalId'] != originalId ||
          projection['activeId'] != activeId ||
          projection['baseColor'] != fixedColor ||
          projection['updatedAt'] == null) {
        throw StateError('public-id-projection-not-confirmed');
      }
      if (FirebaseAuth.instance.currentUser?.uid == uid) _completed.add(key);
    } on FirebaseException catch (error) {
      // Operational telemetry only: neither ID, phone nor account key logged.
      debugPrint('DEDA legacy active ID proof deferred: ${error.code}');
    } catch (error) {
      debugPrint('DEDA legacy active ID proof deferred: ${error.runtimeType}');
    } finally {
      _inFlight.remove(key);
    }
  }
}
