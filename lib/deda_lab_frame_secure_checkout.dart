import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

/// DEDA point 01 — trusted 13-LAB-frame checkout candidate.
///
/// SAFETY GATE: NEVER enable before published Firestore rules and all verified
/// personal diamond sources are reconciled, audited and approved by the owner.
/// The screen's combined visible diamonds ARE NOT proven spendable diamonds.
/// Nothing here edits administrative gift pools or mints currency.
class DedaLabFrameSecureCheckout {
  const DedaLabFrameSecureCheckout._();

  static const int priceDiamonds = 1000;
  static const bool live = bool.fromEnvironment(
    'DEDA_LAB_FRAME_ATOMIC_CHECKOUT_APPROVED',
    defaultValue: false,
  );

  static const Set<String> paidFrameIds = <String>{
    'FRAME_03', 'FRAME_05', 'FRAME_06', 'FRAME_07', 'FRAME_08',
    'FRAME_09', 'FRAME_10', 'FRAME_11', 'FRAME_12', 'FRAME_13',
    'FRAME_14', 'FRAME_15', 'FRAME_16',
  };
  static final RegExp originalIdPattern = RegExp(r'^@DEDA-[A-Z0-9]{6}$');

  static String purchaseId(String originalId, String frameId) {
    if (!originalIdPattern.hasMatch(originalId) ||
        !paidFrameIds.contains(frameId)) {
      throw ArgumentError('unapproved-frame-or-original-identifier');
    }
    return '${originalId}_$frameId';
  }

  static Future<String> _verifyOwner(String originalId) async {
    if (!live || Firebase.apps.isEmpty) {
      throw StateError('secure-lab-frame-checkout-not-approved');
    }
    if (!originalIdPattern.hasMatch(originalId)) {
      throw ArgumentError('original-account-id-required');
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid.isEmpty) {
      throw StateError('signed-in-user-required');
    }
    final uid = user.uid;
    final db = FirebaseFirestore.instance;
    final docs = await Future.wait([
      db.collection('users').doc(uid).get(const GetOptions(source: Source.server)),
      db.collection('deda_sessions').doc(uid).get(const GetOptions(source: Source.server)),
      db.collection('deda_share_ids').doc(originalId).get(const GetOptions(source: Source.server)),
    ]);
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('account-changed-during-checkout');
    }
    final profile = docs[0].data() ?? <String, dynamic>{};
    final session = docs[1].data() ?? <String, dynamic>{};
    final id = docs[2].data() ?? <String, dynamic>{};
    final accountKey = (profile['accountKey'] ?? '').toString().trim();
    if (accountKey.isEmpty ||
        accountKey != (session['accountKey'] ?? '').toString().trim() ||
        profile['sharePersonalId'] != originalId ||
        id['kind'] != 'personal' || id['active'] != true) {
      throw StateError('original-owner-session-not-verified');
    }
    // Published rules must independently authorize this UID/original account.
    return uid;
  }

  static DocumentReference<Map<String, dynamic>> _wallet(
    FirebaseFirestore db, String originalId,
  ) => db.collection('deda_diamond_gift_balances').doc(originalId);

  static DocumentReference<Map<String, dynamic>> _receipt(
    FirebaseFirestore db, String originalId, String frameId,
  ) => db.collection('deda_lab_frame_receipts')
      .doc(originalId).collection('frames').doc(frameId);

  static DocumentReference<Map<String, dynamic>> _ownership(
    FirebaseFirestore db, String originalId, String frameId,
  ) => db.collection('deda_lab_owned_frames')
      .doc(originalId).collection('frames').doc(frameId);

  static bool _valid(
    Map<String, dynamic>? receipt, Map<String, dynamic>? owned,
    String originalId, String frameId,
  ) =>
      receipt != null && owned != null &&
      receipt['kind'] == 'lab_frame' &&
      receipt['publicId'] == originalId &&
      receipt['frameId'] == frameId &&
      receipt['cost'] == priceDiamonds &&
      owned['publicId'] == originalId &&
      owned['frameId'] == frameId &&
      owned['receiptId'] == purchaseId(originalId, frameId);

  /// Readback is the sole valid source of paid ownership on all devices.
  static Future<bool> isOwned({
    required String originalId, required String frameId,
  }) async {
    final uid = await _verifyOwner(originalId);
    purchaseId(originalId, frameId);
    final db = FirebaseFirestore.instance;
    final data = await Future.wait([
      _receipt(db, originalId, frameId).get(const GetOptions(source: Source.server)), _ownership(db, originalId, frameId).get(const GetOptions(source: Source.server)),
    ]);
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('account-switched');
    }
    if (!data[0].exists && !data[1].exists) return false;
    if (!_valid(data[0].data(), data[1].data(), originalId, frameId)) {
      throw StateError('partial-or-forged-frame-ownership');
    }
    return true;
  }

  /// DEDA_100377_MY_STORE_ALL_13_OWNED_FRAMES_SERVER_ONLY
  /// An inventory scan is READ ONLY. Verify signed original account once,
  /// then check both server receipt and account-owned record for every
  /// authentic paid LAB frame. Selected style and offline cache never count.
  static Future<Set<String>> verifiedOwnedFrameIds(String originalId) async {
    final uid = await _verifyOwner(originalId);
    final db = FirebaseFirestore.instance;
    final ids = paidFrameIds.toList()..sort();
    final checks = await Future.wait<String?>(ids.map((frameId) async {
      try {
        final pair = await Future.wait([
          _receipt(db, originalId, frameId)
              .get(const GetOptions(source: Source.server)),
          _ownership(db, originalId, frameId)
              .get(const GetOptions(source: Source.server)),
        ]);
        if (!pair[0].exists && !pair[1].exists) {
          return null;
        }
        if (!_valid(pair[0].data(), pair[1].data(),
                    originalId, frameId)) {
          return null;
        }
        return frameId;
      } catch (_) {
        // No offline/local guess and no forged or partial receipt.
        return null;
      }
    }));
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('account-switched-during-frame-inventory');
    }
    return Set<String>.unmodifiable(checks.whereType<String>());
  }

  /// Transaction is idempotent per original account + frame.
  /// If the response is lost, caller must first retry isOwned, not show
  /// success or debit locally. ONLY server-authenticated wallet is eligible.
  static Future<void> buyOnce({
    required String originalId, required String frameId,
  }) async {
    final uid = await _verifyOwner(originalId);
    final id = purchaseId(originalId, frameId);
    final db = FirebaseFirestore.instance;
    final wallet = _wallet(db, originalId);
    final receipt = _receipt(db, originalId, frameId);
    final owned = _ownership(db, originalId, frameId);
    await db.runTransaction<void>((tx) async {
      // Firestore requires all reads before any write.
      final funds = await tx.get(wallet);
      final existingReceipt = await tx.get(receipt);
      final existingOwned = await tx.get(owned);
      if (FirebaseAuth.instance.currentUser?.uid != uid) {
        throw StateError('account-switched');
      }
      if (existingReceipt.exists || existingOwned.exists) {
        if (!_valid(existingReceipt.data(), existingOwned.data(),
                    originalId, frameId)) {
          throw StateError('frame-receipt-integrity-failure');
        }
        return; // Already owned: never deduct twice.
      }
      final money = funds.data();
      final amount = money?['balance'];
      if (!funds.exists || money?['publicId'] != originalId ||
          amount is! int || amount < priceDiamonds) {
        throw StateError('insufficient-verified-gift-diamonds');
      }
      tx.update(wallet, <String, dynamic>{
        'balance': amount - priceDiamonds,
        'lastLabFrameId': frameId,
        'lastLabFrameReceiptId': id,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      tx.set(receipt, <String, dynamic>{
        'publicId': originalId,
        'frameId': frameId,
        'kind': 'lab_frame',
        'cost': priceDiamonds,
        'createdAt': FieldValue.serverTimestamp(),
      });
      tx.set(owned, <String, dynamic>{
        'publicId': originalId,
        'frameId': frameId,
        'receiptId': id,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
    if (!await isOwned(originalId: originalId, frameId: frameId)) {
      throw StateError('purchase-not-confirmed-by-server-readback');
    }
  }
}
