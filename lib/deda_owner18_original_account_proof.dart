import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'deda_qa32_manager_original_owner_proof.dart';

/// Preserve canonical ACCOUNT ownership when Firebase anonymous UID changes
/// after a legitimate PIN sign-in on another device. Never repairs sessions,
/// changes account records or trusts a locally selected premium alias.
class DedaOwner18OriginalAccountProof {
  static bool scopeMatches(
      {required String original,
      required String uid,
      required Map<String, dynamic> account,
      required Map<String, dynamic> session,
      required Map<String, dynamic> route}) {
    final key = account['accountKey'];
    return RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(original) &&
        uid.isNotEmpty &&
        key is String &&
        key.isNotEmpty &&
        key == session['accountKey'] &&
        (account['sharePersonalId'] == null ||
            account['sharePersonalId'] == original) &&
        route['publicId'] == original &&
        route['kind'] == 'personal' &&
        route['active'] == true &&
        route['ownerUid'] is String &&
        (route['ownerUid'] as String).isNotEmpty;
  }

  static Future<String> verify(String original) async {
    if (Firebase.apps.isEmpty) throw StateError('firebase-not-ready');
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('signed-in-account-required');
    final db = FirebaseFirestore.instance;
    final docs = await Future.wait([
      db
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.server)),
      db
          .collection('deda_sessions')
          .doc(uid)
          .get(const GetOptions(source: Source.server)),
      db
          .collection('deda_share_ids')
          .doc(original)
          .get(const GetOptions(source: Source.server)),
    ]);
    final account = docs[0].data() ?? <String, dynamic>{};
    final session = docs[1].data() ?? <String, dynamic>{};
    final route = docs[2].data() ?? <String, dynamic>{};
    if (FirebaseAuth.instance.currentUser?.uid != uid ||
        !scopeMatches(
            original: original,
            uid: uid,
            account: account,
            session: session,
            route: route)) {
      throw StateError('canonical-account-session-mismatch');
    }
    if (route['ownerUid'] == uid) {
      if (!DedaQa32ManagerOriginalOwnerProof.authentic(
          expectedOriginal: original,
          authUid: uid,
          account: account,
          session: session,
          route: route)) {
        throw StateError('original-owner-not-proven');
      }
    } else {
      if (account['sharePersonalId'] != original) {
        throw StateError('canonical-original-required-on-new-device');
      }
      // Existing deployed rule verifiedDiamondsPersonalOwner independently
      // checks the registered route owner's accountKey against THIS signed-in
      // PIN session. An ABSENT receipt is readable for its true account only.
      // This read does not create a receipt, grant an item or touch any funds.
      await db
          .collection('deda_lab_frame_receipts')
          .doc(original)
          .collection('frames')
          .doc('FRAME_03')
          .get(const GetOptions(source: Source.server));
    }
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('account-changed-during-owner-proof');
    }
    return uid;
  }
}
