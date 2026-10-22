import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'deda_stage71_free_manager_200_service.dart';
import 'deda_qa32_manager_original_owner_proof.dart';

/// Permanent, user-confirmed reception of an ALREADY gifted free identifier.
/// Never creates premium ownership, never changes original IDs, and never
/// accesses any gems/diamonds, payments, places or legacy gifts.
class DedaStage74IdGift {
  final String identifier;
  final String originalId;
  final String group;
  final String baseColor;
  final bool received;
  final DateTime? receivedAt;

  const DedaStage74IdGift({
    required this.identifier,
    required this.originalId,
    required this.group,
    required this.baseColor,
    required this.received,
    this.receivedAt,
  });
}

class DedaStage74IdGiftService {
  DedaStage74IdGiftService._();

  static const receiptCollection = 'deda_stage74_id_gift_receipts';
  static bool get enabled => DedaStage71Admin200.enabled;

  static Future<String> _verifiedOwner(String originalId) async {
    if (!enabled || Firebase.apps.isEmpty ||
        !RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(originalId)) {
      throw StateError('gift-inbox-not-authorized');
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('gift-recipient-not-signed-in');
    final db = FirebaseFirestore.instance;
    // DEDA_100377_POINT08_LEGACY_GIFT_RECIPIENT_UID_ORIGINAL_ROUTE_PROOF
    // The recipient's ORIGINAL account identity is bound by three
    // authoritative server records; a missing legacy sharePersonalId is
    // permitted only when account/session keys and the owned ID route match.
    // This never treats a typed premium alias as the canonical recipient.
    final uid = user.uid;
    final proof = await Future.wait([
      db.collection('users').doc(uid).get(
        const GetOptions(source: Source.server),
      ),
      db.collection('deda_sessions').doc(uid).get(
        const GetOptions(source: Source.server),
      ),
      db.collection('deda_share_ids').doc(originalId).get(
        const GetOptions(source: Source.server),
      ),
    ]);
    final account = proof[0].data() ?? <String, dynamic>{};
    final session = proof[1].data() ?? <String, dynamic>{};
    final route = proof[2].data() ?? <String, dynamic>{};
    if (FirebaseAuth.instance.currentUser?.uid != uid ||
        !DedaQa32ManagerOriginalOwnerProof.authentic(
          expectedOriginal: originalId,
          authUid: uid,
          account: account,
          session: session,
          route: route,
        )) {
      throw StateError('gift-recipient-original-account-mismatch');
    }
    return uid;
  }

  static Future<List<DedaStage74IdGift>> load(String originalId) async {
    final uid = await _verifiedOwner(originalId);
    final db = FirebaseFirestore.instance;
    final gifts = await db.collection(DedaStage71Admin200.registry)
        .where('recipientOriginalId', isEqualTo: originalId)
        .limit(200)
        .get(const GetOptions(source: Source.server));
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('gift-recipient-session-changed');
    }
    // A receipt is owned by the same ID as the unique immutable grant.
    // Read ONLY the recipient's records; no private GM inventory reads.
    final receipts = await db.collection(receiptCollection)
        .where('originalId', isEqualTo: originalId)
        .limit(200)
        .get(const GetOptions(source: Source.server));
    final byId = {for (final r in receipts.docs) r.id: r.data()};
    final rows = <DedaStage74IdGift>[];
    for (final gift in gifts.docs) {
      final d = gift.data();
      if (d['identifier'] != gift.id ||
          d['recipientOriginalId'] != originalId ||
          !{'001', '002'}.contains(d['group']) ||
          !{'gold', 'diamond', 'royal', 'pink'}.contains(d['baseColor']) ||
          d['kind'] != 'gifted') {
        // GM self-use is not a sent gift and is not claimed as one.
        continue;
      }
      final receipt = byId[gift.id];
      // DEDA_100377_GIFT_RECEIPT_REQUIRES_SERVER_TIMESTAMP
      // An incomplete receipt is NOT a completed user acceptance.
      final validReceipt = receipt != null &&
          receipt['identifier'] == gift.id &&
          receipt['originalId'] == originalId &&
          receipt['group'] == d['group'] &&
          receipt['receivedAt'] is Timestamp;
      if (receipt != null && !validReceipt) {
        throw StateError('id-gift-receipt-mismatch');
      }
      rows.add(DedaStage74IdGift(
        identifier: gift.id, originalId: originalId,
        group: d['group'] as String,
        baseColor: d['baseColor'] as String,
        received: validReceipt,
        receivedAt: receipt?['receivedAt'] is Timestamp
            ? (receipt!['receivedAt'] as Timestamp).toDate()
            : null,
      ));
    }
    rows.sort((a,b) {
      if (a.received != b.received) return a.received ? 1 : -1;
      return a.identifier.compareTo(b.identifier);
    });
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('id-gift-recipient-session-rotated');
    }
    return rows;
  }

  /// Idempotent claim. The grant already exists on the server; this simply
  /// acknowledges receipt once and records immutable receipt history.
  static Future<void> receive(DedaStage74IdGift gift) async {
    final uid = await _verifiedOwner(gift.originalId);
    if (gift.received) return;
    final db = FirebaseFirestore.instance;
    final grant = db.collection(DedaStage71Admin200.registry)
        .doc(gift.identifier);
    final receipt = db.collection(receiptCollection).doc(gift.identifier);
    await db.runTransaction<void>((transaction) async {
      final issued = await transaction.get(grant);
      final existing = await transaction.get(receipt);
      final row = issued.data();
      if (FirebaseAuth.instance.currentUser?.uid != uid ||
          row == null ||
          row['identifier'] != gift.identifier ||
          row['recipientOriginalId'] != gift.originalId ||
          row['kind'] != 'gifted' ||
          row['group'] != gift.group ||
          row['baseColor'] != gift.baseColor) {
        throw StateError('original-gift-ownership-not-verified');
      }
      if (existing.exists) {
        final data = existing.data()!;
        if (data['identifier'] != gift.identifier ||
            data['originalId'] != gift.originalId ||
            data['group'] != gift.group) {
          throw StateError('different-existing-id-gift-receipt');
        }
        return;
      }
      transaction.set(receipt, {
        'identifier': gift.identifier,
        'originalId': gift.originalId,
        'group': gift.group,
        'receivedAt': FieldValue.serverTimestamp(),
      });
    });
    final confirmed = await receipt.get(const GetOptions(source: Source.server));
    final data = confirmed.data();
    if (FirebaseAuth.instance.currentUser?.uid != uid ||
        data == null ||
        data['identifier'] != gift.identifier ||
        data['originalId'] != gift.originalId ||
        data['group'] != gift.group ||
        data['receivedAt'] is! Timestamp) {
      throw StateError('gift-receipt-readback-unconfirmed');
    }
  }

  static Future<Set<String>> receivedNames(String originalId) async {
    final rows = await load(originalId);
    return rows.where((gift) => gift.received)
        .map((gift) => gift.identifier).toSet();
  }

  static Future<bool> isReceived(String originalId, String identifier) async {
    final uid = await _verifiedOwner(originalId);
    final receipt = await FirebaseFirestore.instance
        .collection(receiptCollection).doc(identifier)
        .get(const GetOptions(source: Source.server));
    final d = receipt.data();
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('id-gift-user-changed');
    }
    return d != null && d['identifier'] == identifier &&
        d['originalId'] == originalId &&
        d['receivedAt'] is Timestamp;
  }
}
