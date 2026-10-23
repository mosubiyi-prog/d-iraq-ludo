import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'deda_owner18_original_account_proof.dart';

/// Account backup of the EXISTING native cosmetic shop and selections.
/// No funds, XP, identifier ownership or account fields are written here.
class DedaOwner18Cosmetics {
  static const collection = 'deda_native_account_cosmetics';
  static Future<String> requireOwner(String original) =>
      DedaOwner18OriginalAccountProof.verify(original);

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
      'pendingFrames': FieldValue.arrayRemove([frame]),
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

  static Future<bool> beginNativeFrame(String original, String frame) async {
    final uid = await requireOwner(original);
    return FirebaseFirestore.instance.runTransaction<bool>((tx) async {
      final snap = await tx.get(ref(original));
      sameOwner(uid);
      final data = snap.data() ?? <String, dynamic>{};
      if (data['ownedFrames'] is List &&
          (data['ownedFrames'] as List).contains(frame)) return false;
      if (data['pendingFrames'] is List &&
          (data['pendingFrames'] as List).contains(frame)) {
        throw StateError('native-frame-purchase-already-pending');
      }
      tx.set(
          ref(original),
          {
            'originalId': original,
            'pendingFrames': FieldValue.arrayUnion([frame]),
            'updatedAt': FieldValue.serverTimestamp()
          },
          SetOptions(merge: true));
      return true;
    });
  }

  static Future<void> cancelUnchargedFrame(
      String original, String frame) async {
    final uid = await requireOwner(original);
    await ref(original).update({
      'pendingFrames': FieldValue.arrayRemove([frame]),
      'updatedAt': FieldValue.serverTimestamp()
    });
    sameOwner(uid);
  }
}
