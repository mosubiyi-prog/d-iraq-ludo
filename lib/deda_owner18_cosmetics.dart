import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'deda_qa32_manager_original_owner_proof.dart';

/// Account backup of the EXISTING native cosmetic shop and selections.
/// No funds, XP, identifier ownership or account fields are written here.
class DedaOwner18Cosmetics {
  static const collection = 'deda_native_account_cosmetics';
  static Future<String> requireOwner(String original) async {
    if (Firebase.apps.isEmpty) throw StateError('firebase-not-ready');
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || !RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(original)) {
      throw StateError('original-owner-required');
    }
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
    if (FirebaseAuth.instance.currentUser?.uid != uid ||
        !DedaQa32ManagerOriginalOwnerProof.authentic(
            expectedOriginal: original,
            authUid: uid,
            account: docs[0].data() ?? {},
            session: docs[1].data() ?? {},
            route: docs[2].data() ?? {})) {
      throw StateError('account-changed-or-owner-unverified');
    }
    return uid;
  }

  static void sameOwner(String uid) {
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('account-changed');
    }
  }

  static DocumentReference<Map<String, dynamic>> ref(String original) =>
      FirebaseFirestore.instance.collection(collection).doc(original);

  static Future<Map<String, dynamic>> read(String original) async {
    final uid = await requireOwner(original);
    final snap =
        await ref(original).get(const GetOptions(source: Source.server));
    sameOwner(uid);
    final data = snap.data();
    if (data == null) return {};
    if (data['originalId'] != original)
      throw StateError('wrong-cosmetic-owner');
    return data;
  }

  static Future<void> backupInventory(
      String original, Set<String> owned, Set<String> activeBadges) async {
    final uid = await requireOwner(original);
    await ref(original).set({
      'originalId': original,
      'ownedStyles': FieldValue.arrayUnion(owned.toList()),
      'activeBadges': activeBadges.toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    sameOwner(uid);
  }

  static Future<void> saveAppearance(
    String original, {
    required int avatar,
    required int frame,
    required int background,
  }) async {
    final uid = await requireOwner(original);
    await ref(original).set({
      'originalId': original,
      'avatar': avatar,
      'frame': frame,
      'background': background,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    sameOwner(uid);
  }

  static Future<void> prepare(String original) async {
    final uid = await requireOwner(original);
    await ref(original).set(
        {'originalId': original, 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true));
    sameOwner(uid);
  }

  static Future<void> confirmNativeFrame(String original, String frame) async {
    final uid = await requireOwner(original);
    await ref(original).set({
      'originalId': original,
      'ownedFrames': FieldValue.arrayUnion([frame]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    sameOwner(uid);
    final proof = await read(original);
    sameOwner(uid);
    if (!(proof['ownedFrames'] is List &&
        (proof['ownedFrames'] as List).contains(frame))) {
      throw StateError('frame-account-save-unconfirmed');
    }
  }
}
