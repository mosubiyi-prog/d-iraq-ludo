import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
      await db.runTransaction((tx) async {
        // All reads happen before any write.
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
          throw StateError('legacy-public-proof-not-authorized');
        }
        if (user['sharePersonalId'] != originalId) {
          tx.update(userRef, {'sharePersonalId': originalId});
        }
        if (active == null) {
          // Never create a normal row while an unconfirmed premium is active.
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
      await DedaActiveIdPublicSync100409.publishAfterVerifiedRead(
        uid: uid, originalId: originalId, activeId: activeId,
        fixedColor: fixedColor,
      );
      if (FirebaseAuth.instance.currentUser?.uid == uid) _completed.add(key);
    } catch (_) {
      // Do not fabricate normal status if security rules or server deny repair.
      // The next owner-authenticated session may retry.
    } finally {
      _inFlight.remove(key);
    }
  }
}
