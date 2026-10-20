import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

/// Stage67 Spark-compatible client transport for ONE protected source:
/// authenticated server-recorded DEDA received-gift/verified-Telegram wallet.
///
/// Works only together with audited and DEPLOYED Stage66 candidate rules.
/// This class does not convert locally accumulated rewarded-ad diamonds into
/// trusted value, activate Firebase Functions or access GM exclusive100.
/// Any security failure is DENIED; NEVER optimistically mark a card owned.
/// No production screen may turn on this transport before live rules are
/// reconciled with the actual active Firestore ruleset.
class DedaStage67SparkCardCheckout {
  const DedaStage67SparkCardCheckout._();

  static const priceDiamonds = 5000;
  static const live = bool.fromEnvironment(
    'DEDA_STAGE67_VERIFIED_GIFT_CARD_RULES_DEPLOYED',
    defaultValue: false,
  );
  static const styles = {'gold', 'diamond', 'royal', 'pink'};
  static final RegExp originalPattern = RegExp(r'^@DEDA-[A-Z0-9]{6}$');

  static String receiptId(String originalId, String style) {
    if (!originalPattern.hasMatch(originalId) || !styles.contains(style)) {
      throw ArgumentError('invalid-original-id-or-style');
    }
    return '${originalId}_$style';
  }

  static Future<String> _trustedUid(String originalId) async {
    if (!live || Firebase.apps.isEmpty || !originalPattern.hasMatch(originalId)) {
      throw StateError('verified-server-gift-wallet-not-active');
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid.isEmpty) {
      throw StateError('authenticated-deda-account-required');
    }
    final db = FirebaseFirestore.instance;
    final docs = await Future.wait([
      db.collection('users').doc(user.uid).get(),
      db.collection('deda_sessions').doc(user.uid).get(),
      db.collection('deda_share_ids').doc(originalId).get(),
    ]);
    if (FirebaseAuth.instance.currentUser?.uid != user.uid) {
      throw StateError('account-changed-during-checkout');
    }
    final profile = docs[0].data() ?? {};
    final session = docs[1].data() ?? {};
    final original = docs[2].data() ?? {};
    final accountKey = (profile['accountKey'] ?? '').toString().trim();
    if (accountKey.isEmpty ||
        accountKey != (session['accountKey'] ?? '').toString().trim() ||
        (profile['sharePersonalId'] ?? '').toString() != originalId ||
        original['kind'] != 'personal' ||
        original['active'] != true) {
      throw StateError('original-account-or-pin-session-not-verified');
    }
    final registeredUid = (original['ownerUid'] ?? '').toString();
    if (registeredUid.isEmpty) {
      throw StateError('original-owner-unverified');
    }
    // Firestore security rules are the final authority for rotated UIDs.
    // Never trust phone/name alone to grant ownership.
    return user.uid;
  }

  static DocumentReference<Map<String, dynamic>> _wallet(
    FirebaseFirestore db, String originalId,
  ) => db.collection('deda_diamond_gift_balances').doc(originalId);

  static DocumentReference<Map<String, dynamic>> _receipt(
    FirebaseFirestore db, String id,
  ) => db.collection('deda_stage66_card_receipts').doc(id);

  static DocumentReference<Map<String, dynamic>> _card(
    FirebaseFirestore db, String id,
  ) => db.collection('deda_stage66_owned_cards').doc(id);

  static bool _validReceipt(
    Map<String, dynamic>? receipt,
    Map<String, dynamic>? card,
    String originalId,
    String style,
  ) =>
      receipt != null &&
      card != null &&
      receipt['publicId'] == originalId &&
      receipt['kind'] == 'card' &&
      receipt['style'] == style &&
      receipt['cost'] == priceDiamonds &&
      card['publicId'] == originalId &&
      card['style'] == style &&
      card['receiptId'] == receiptId(originalId, style);

  static Future<bool> isOwned({
    required String originalId,
    required String style,
  }) async {
    final uid = await _trustedUid(originalId);
    final db = FirebaseFirestore.instance;
    final id = receiptId(originalId, style);
    final snapshots = await Future.wait([
      _receipt(db, id).get(),
      _card(db, id).get(),
    ]);
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('account-changed');
    }
    if (!snapshots[0].exists && !snapshots[1].exists) return false;
    if (!_validReceipt(
      snapshots[0].data(), snapshots[1].data(), originalId, style,
    )) {
      throw StateError('card-receipt-integrity-failed');
    }
    return true;
  }

  static Future<int> trustedGiftBalance(String originalId) async {
    final uid = await _trustedUid(originalId);
    final data = (await _wallet(FirebaseFirestore.instance, originalId).get())
        .data();
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('account-changed');
    }
    if (data == null) return 0;
    final amount = data['balance'];
    if (data['publicId'] != originalId || amount is! int || amount < 0) {
      throw StateError('unverified-server-balance');
    }
    return amount;
  }

  /// Real Firestore transaction: wallet -5000 + immutable receipt +
  /// immutable ownership. Can only succeed if *deployed* rules accept all 3
  /// documents together. Concurrent attempts retry/deny instead of overdraft.
  static Future<bool> buyCard({
    required String originalId,
    required String style,
  }) async {
    final uid = await _trustedUid(originalId);
    final db = FirebaseFirestore.instance;
    final id = receiptId(originalId, style);
    final wallet = _wallet(db, originalId);
    final receipt = _receipt(db, id);
    final card = _card(db, id);

    final alreadyOwned = await db.runTransaction<bool>((tx) async {
      final funds = await tx.get(wallet);
      final oldReceipt = await tx.get(receipt);
      final oldCard = await tx.get(card);
      if (FirebaseAuth.instance.currentUser?.uid != uid) {
        throw StateError('account-changed');
      }
      if (oldReceipt.exists || oldCard.exists) {
        if (!_validReceipt(
          oldReceipt.data(), oldCard.data(), originalId, style,
        )) {
          throw StateError('card-receipt-integrity-failed');
        }
        return true; // Repeat request: no second charge.
      }
      final money = funds.data();
      if (!funds.exists ||
          money?['publicId'] != originalId ||
          money?['balance'] is! int ||
          (money!['balance'] as int) < priceDiamonds) {
        throw StateError('insufficient-verified-server-gift-diamonds');
      }
      final balance = money['balance'] as int;
      tx.update(wallet, {
        'balance': balance - priceDiamonds,
        'lastPurchaseStyle': style,
        'lastPurchaseReceiptId': id,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      tx.set(receipt, {
        'publicId': originalId,
        'style': style,
        'kind': 'card',
        'cost': priceDiamonds,
        'createdAt': FieldValue.serverTimestamp(),
      });
      tx.set(card, {
        'publicId': originalId,
        'style': style,
        'receiptId': id,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return false;
    });
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('account-changed');
    }
    if (!await isOwned(originalId: originalId, style: style)) {
      throw StateError('purchase-not-verified-on-server');
    }
    return alreadyOwned;
  }
}
