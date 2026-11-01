import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

/// Opt-in Spark Firestore identity anchor. This cannot restore, grant or
/// move ANY wallet, profile, premium ID, league, gift or user entitlement.
/// The old 100340/100420 sign-in path is deliberately not replaced.
class DedaFreeFirestoreRecoveryHold {
  static const _anchors = 'deda_recovery_original_anchors';
  static const _locks = 'deda_recovery_original_locks';
  static const _holds = 'deda_recovery_identity_holds';

  static bool validOriginal(String original) =>
      RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(original);

  static bool validAccount(String accountKey) =>
      RegExp(r'^[0-9]{8,15}$').hasMatch(accountKey);

  static bool validAnchor(Object? data, String accountKey) {
    if (data is! Map || !validAccount(accountKey)) return false;
    final original = data['originalId'];
    final sourceUid = data['sourceUid'];
    return data['accountKey'] == accountKey &&
        original is String && validOriginal(original) &&
        sourceUid is String && sourceUid.isNotEmpty;
  }

  static bool isHoldOnly(Object? data, String uid, String accountKey,
      String original, String sourceUid) {
    if (data is! Map) return false;
    return data['uid'] == uid &&
        data['accountKey'] == accountKey &&
        data['originalId'] == original &&
        data['sourceUid'] == sourceUid &&
        data['status'] == 'PIN_PROVED_HOLD' &&
        data['canRestoreAssets'] == false &&
        data['canMigrate'] == false &&
        data['canCreditXp'] == false &&
        data['canCreditDiamonds'] == false &&
        data['canIssueGift'] == false;
  }

  static String _requireAnonymousUid() {
    if (Firebase.apps.isEmpty) throw StateError('firebase-not-ready');
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !user.isAnonymous) {
      throw StateError('anonymous-auth-required');
    }
    return user.uid;
  }

  /// Must be called ONLY after a fresh server-checked legacy PIN attempt,
  /// on the original creator device. Rules enforce that requirement.
  /// The two IDs are created together or not at all.
  static Future<void> enrollOnOriginalDevice({
    required String accountKey,
    required String originalId,
  }) async {
    final uid = _requireAnonymousUid();
    if (!validAccount(accountKey) || !validOriginal(originalId)) {
      throw ArgumentError('invalid-account-or-original-id');
    }
    final db = FirebaseFirestore.instance;
    final anchorRef = db.collection(_anchors).doc(accountKey);
    final old = await anchorRef.get(const GetOptions(source: Source.server));
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('firebase-user-changed');
    }
    if (old.exists) {
      if (!validAnchor(old.data(), accountKey) ||
          old.data()?['sourceUid'] != uid ||
          old.data()?['originalId'] != originalId) {
        throw StateError('original-anchor-conflict');
      }
      return;
    }
    final shared = <String, dynamic>{
      'accountKey': accountKey,
      'originalId': originalId,
      'sourceUid': uid,
      'createdAt': FieldValue.serverTimestamp(),
    };
    final batch = db.batch();
    batch.set(anchorRef, shared);
    batch.set(db.collection(_locks).doc(originalId), shared);
    await batch.commit();
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('firebase-user-changed');
    }
  }

  /// Must be called only after fresh PIN proof on this anonymous UID.
  /// Reads immutable original ID by account number; cannot credit assets.
  static Future<String> verifyOnNewDevice({
    required String accountKey,
  }) async {
    final uid = _requireAnonymousUid();
    if (!validAccount(accountKey)) throw ArgumentError('invalid-account-key');
    final db = FirebaseFirestore.instance;
    final anchor = await db.collection(_anchors).doc(accountKey)
        .get(const GetOptions(source: Source.server));
    if (FirebaseAuth.instance.currentUser?.uid != uid ||
        !validAnchor(anchor.data(), accountKey)) {
      throw StateError('original-identity-not-enrolled');
    }
    final original = anchor.data()!['originalId'] as String;
    final sourceUid = anchor.data()!['sourceUid'] as String;
    final ref = db.collection(_holds).doc(uid);
    final previous = await ref.get(const GetOptions(source: Source.server));
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('firebase-user-changed');
    }
    if (previous.exists) {
      if (!isHoldOnly(previous.data(), uid, accountKey, original, sourceUid)) {
        throw StateError('recovery-hold-conflict');
      }
    } else {
      await ref.set(<String, dynamic>{
        'uid': uid,
        'accountKey': accountKey,
        'originalId': original,
        'sourceUid': sourceUid,
        'status': 'PIN_PROVED_HOLD',
        'createdAt': FieldValue.serverTimestamp(),
        'canRestoreAssets': false,
        'canMigrate': false,
        'canCreditXp': false,
        'canCreditDiamonds': false,
        'canIssueGift': false,
      });
    }
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('firebase-user-changed');
    }
    return original;
  }
}
