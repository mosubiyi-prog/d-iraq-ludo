import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'deda_100431_linked_owner_session_policy.dart';
import 'deda_lab_frame_secure_checkout.dart';
import 'deda_owned_frame_reader.dart';
import 'deda_stage67_spark_secure_card_checkout.dart';
import 'deda_stage71_free_owned_use_profile.dart';

/// Step 2: source-only account asset readback. NEVER a financial migration.
/// No APK production enablement until all 100340 legacy financial writers are
/// fenced, historical receipts are audited, and two real phones pass QA.
const bool dedaStep2AssetsReadbackEnabled = bool.fromEnvironment(
  'DEDA_STEP2_ASSETS_READBACK', defaultValue: false);

class DedaStep2AssetsHold implements Exception {
  const DedaStep2AssetsHold(this.reason);
  final String reason;
  @override
  String toString() => 'DedaStep2AssetsHold($reason)';
}

class DedaStep2CloudDocument {
  const DedaStep2CloudDocument(this.fields, {
    this.isFromCache = false, this.hasPendingWrites = false,
  });
  final Map<String, dynamic>? fields;
  final bool isFromCache, hasPendingWrites;
}

abstract class DedaStep2AssetsIo {
  Future<DedaStep2CloudDocument> server(String path);
  /// Strict 13-frame receipt+ownership reader, NEVER purchase/claim.
  Future<Set<String>> ownedFrameIds(String originalId);
  /// Already accepted Stage71 grants; gifted IDs require Stage74 receipt.
  Future<Set<String>> acceptedOwnedPremiumIds(String originalId);
}

class DedaStep2FirebaseAssetsIo implements DedaStep2AssetsIo {
  const DedaStep2FirebaseAssetsIo();
  @override
  Future<DedaStep2CloudDocument> server(String path) async {
    final snapshot = await FirebaseFirestore.instance.doc(path)
        .get(const GetOptions(source: Source.server));
    return DedaStep2CloudDocument(snapshot.data(),
      isFromCache: snapshot.metadata.isFromCache,
      hasPendingWrites: snapshot.metadata.hasPendingWrites);
  }

  @override
  Future<Set<String>> ownedFrameIds(String originalId) =>
      DedaOwnedFrameReader(
        DedaFirebaseOwnedFrameReadIo(),
        frameIds: DedaLabFrameSecureCheckout.paidFrameIds,
      ).owned(originalId);

  @override
  Future<Set<String>> acceptedOwnedPremiumIds(String originalId) async {
    final rows = await DedaStage71OwnedIdentifierService
        .acceptedOwnedForMyStore(originalId);
    return Set<String>.unmodifiable(rows.map((row) => row.identifier));
  }
}

/// Readback is indexed by the IMMUTABLE personal ID, never active premium ID.
/// Values are OBSERVATIONS and cannot be credited, debited or advertised as
/// a reconstructed full account. A missing wallet is UNKNOWN, not zero.
class DedaStep2AssetsEvidence {
  const DedaStep2AssetsEvidence({
    required this.accountKey,
    required this.originalId,
    required this.originalUid,
    required this.accountName,
    required this.accountType,
    required this.verifiedPaidFrameIds,
    required this.verifiedPaidCardStyles,
    required this.verifiedAcceptedPremiumIds,
    required this.receivedGiftWalletBalance,
    required this.managerPersonalBalance,
    required this.activeDisplayId,
    required this.currentWeeklyXp,
    required this.serverSources,
  });

  final String accountKey, originalId, originalUid;
  final String accountName, accountType;
  final Set<String> verifiedPaidFrameIds;
  /// Receipt-backed only; missing historical local items remain unknown.
  final Set<String> verifiedPaidCardStyles, verifiedAcceptedPremiumIds;
  final int? receivedGiftWalletBalance, managerPersonalBalance;
  final String? activeDisplayId;
  final int? currentWeeklyXp;
  final Map<String, String> serverSources;

  /// Existing gift-wallet + reviewed manager wallet are NOT all user
  /// diamond sources, and an ID selection is NOT proof of premium ownership.
  bool get fullAccountRestored => false;
  bool get canRestoreDiamonds => false;
  bool get canReissueWeeklyPrizes => false;
  bool get canReissueGifts => false;
  bool get canTransferPurchasedFrames => false;
  bool get canActivatePremiumId => false;
}

/// Bounded, source-only inventory for the SAME linked Firebase UID.
/// No write APIs are exposed. All checks fail closed on network ambiguity or
/// changed session; legacy 100340 unverified local sources stay on HOLD.
class DedaStep2AssetsReadback {
  const DedaStep2AssetsReadback({
    required this.io,
    required this.currentUid,
    required this.verifyOriginalOwner,
    this.enabled = dedaStep2AssetsReadbackEnabled,
  });

  factory DedaStep2AssetsReadback.firebase() => DedaStep2AssetsReadback(
    io: const DedaStep2FirebaseAssetsIo(),
    currentUid: () => FirebaseAuth.instance.currentUser?.uid,
    verifyOriginalOwner: (uid, account) async {
      final user = FirebaseAuth.instance.currentUser;
      return user?.uid == uid &&
          await DedaLinkedOwnerSessionPolicy.verified(user, account);
    },
  );

  final DedaStep2AssetsIo io;
  final String? Function() currentUid;
  final Future<bool> Function(String uid, String accountKey)
      verifyOriginalOwner;
  final bool enabled;

  void _check(String uid, bool Function() isCurrent) {
    if (!enabled || uid.isEmpty || currentUid() != uid || !isCurrent()) {
      throw const DedaStep2AssetsHold('owner-or-build-not-authorized');
    }
  }

  Future<Map<String, dynamic>?> _read(
      String path, String uid, bool Function() isCurrent) async {
    _check(uid, isCurrent);
    final result = await io.server(path);
    _check(uid, isCurrent);
    if (result.isFromCache || result.hasPendingWrites) {
      throw const DedaStep2AssetsHold('not-authoritative-server-source');
    }
    return result.fields;
  }

  static int _amount(Object? value, String label) {
    if (value is! int || value < 0 || value > 9007199254740991) {
      throw DedaStep2AssetsHold('invalid-$label-amount');
    }
    return value;
  }

  Future<DedaStep2AssetsEvidence> inspect({
    required String accountKey,
    required String originalId,
    required String originalUid,
    String? weekId,
    required bool Function() isCurrent,
  }) async {
    if (!RegExp(r'^[0-9]{10,16}$').hasMatch(accountKey) ||
        !RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(originalId) ||
        (weekId != null &&
          !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(weekId))) {
      throw const DedaStep2AssetsHold('invalid-original-asset-scope');
    }
    _check(originalUid, isCurrent);
    if (!await verifyOriginalOwner(originalUid, accountKey)) {
      throw const DedaStep2AssetsHold('original-owner-proof-missing');
    }
    _check(originalUid, isCurrent);

    final route = await _read('deda_share_ids/$originalId',
      originalUid, isCurrent);
    if (route?['publicId'] != originalId ||
        route?['ownerUid'] != originalUid ||
        route?['kind'] != 'personal' || route?['active'] != true) {
      throw const DedaStep2AssetsHold('immutable-original-id-route-conflict');
    }
    final profile = await _read('deda_account_profiles/$accountKey',
      originalUid, isCurrent);
    if (profile == null || profile['accountKey'] != accountKey ||
        profile['name'] is! String ||
        (profile['name'] as String).trim().length < 2 ||
        !['user','placeOwner'].contains(profile['accountType'])) {
      throw const DedaStep2AssetsHold('original-profile-unverified');
    }

    _check(originalUid, isCurrent);
    final frames = await io.ownedFrameIds(originalId);
    _check(originalUid, isCurrent);
    final catalog = DedaLabFrameSecureCheckout.paidFrameIds;
    if (!catalog.containsAll(frames)) {
      throw const DedaStep2AssetsHold('unknown-paid-frame-id');
    }

    // Stage66 has FOUR paid ID cards, separate from the 13 LAB frames.
    // Verify both existing server records. No purchase, debit, or new grant.
    final paidCards = <String>{};
    final styles = DedaStage67SparkCardCheckout.styles.toList()..sort();
    for (final style in styles) {
      final receiptId =
          DedaStage67SparkCardCheckout.receiptId(originalId, style);
      final receipt = await _read('deda_stage66_card_receipts/$receiptId',
          originalUid, isCurrent);
      final owned = await _read('deda_stage66_owned_cards/$receiptId',
          originalUid, isCurrent);
      if (receipt == null && owned == null) continue;
      if (receipt?['publicId'] != originalId ||
          receipt?['kind'] != 'card' ||
          receipt?['style'] != style ||
          receipt?['cost'] != DedaStage67SparkCardCheckout.priceDiamonds ||
          owned?['publicId'] != originalId ||
          owned?['style'] != style ||
          owned?['receiptId'] != receiptId) {
        throw const DedaStep2AssetsHold('paid-card-receipt-ownership-conflict');
      }
      paidCards.add(style);
    }

    // Reuse existing accepted-grant reader with original UID verification and
    // Stage74 received-gift receipt requirement; never infer from activeId.
    _check(originalUid, isCurrent);
    final acceptedPremium = await io.acceptedOwnedPremiumIds(originalId);
    _check(originalUid, isCurrent);
    if (acceptedPremium.length > 200 ||
        acceptedPremium.any((id) =>
          !RegExp(r'^@DEDA-[A-Z0-9]{4,12}$').hasMatch(id))) {
      throw const DedaStep2AssetsHold('premium-grant-source-invalid');
    }

    final gift = await _read('deda_diamond_gift_balances/$originalId',
      originalUid, isCurrent);
    final int? giftBalance;
    if (gift == null) {
      giftBalance = null;
    } else {
      if (gift['publicId'] != originalId) {
        throw const DedaStep2AssetsHold('gift-wallet-not-original-id');
      }
      giftBalance = _amount(gift['balance'], 'gift-wallet');
    }

    // Firestore Rules grant the GM wallet ONLY to a verified general manager.
    // Ordinary owners must NEVER query this restricted document: permission-
    // denied is not proof that their personal account/assets disappeared.
    final gateway = await _read('admin_entry_access/$accountKey',
      originalUid, isCurrent);
    final manager = gateway?['active'] == true &&
        gateway?['status'] == 'active' &&
        gateway?['accessType'] == 'general_manager_gateway' &&
        gateway?['allowedRole'] == 'general_manager';
    int? managerBalance;
    if (manager) {
      // A verified GM account uses its own separate admin recovery policy.
      // Do not grant the ordinary user restore pipeline GM-wallet access.
      throw const DedaStep2AssetsHold(
          'general-manager-recovery-needs-separate-admin-proof');
    }

    final active = await _read('deda_stage71_active_identifier/$originalId',
      originalUid, isCurrent);
    String? activeId;
    if (active != null) {
      if (active['originalId'] != originalId ||
          active['activeId'] is! String ||
          !RegExp(r'^@DEDA-[A-Z0-9]{4,12}$')
              .hasMatch(active['activeId'] as String)) {
        throw const DedaStep2AssetsHold('premium-selection-not-ownership');
      }
      activeId = active['activeId'] as String;
      if (activeId != originalId && !acceptedPremium.contains(activeId)) {
        throw const DedaStep2AssetsHold('active-premium-id-not-owned');
      }
    }

    final leagueOwner = await _read('deda_weekly_direct_accounts/$originalId',
      originalUid, isCurrent);
    if (leagueOwner != null &&
        (leagueOwner['publicId'] != originalId ||
         leagueOwner['accountKey'] != accountKey)) {
      throw const DedaStep2AssetsHold('weekly-league-owner-conflict');
    }
    final week = weekId == null ? null : await _read(
      'deda_weekly_direct_weeks/$weekId/scores/$originalId',
      originalUid, isCurrent);
    int? weeklyXp;
    if (week != null) {
      if (week['publicId'] != originalId || week['weekId'] != weekId) {
        throw const DedaStep2AssetsHold('weekly-league-score-wrong-owner');
      }
      weeklyXp = _amount(week['weeklyXp'], 'weekly-xp');
    }

    _check(originalUid, isCurrent);
    final domains = Map<String,String>.unmodifiable({
      'profile': 'server-profile-verified',
      'paidFrames': 'strict-receipt-and-ownership-pairs-verified',
      'paidIdCards': 'stage66-receipt-and-ownership-pairs-readonly-legacy-unknown',
      'receivedGiftWallet': gift == null ?
        'wallet-absent-unknown-not-zero' : 'existing-wallet-readonly',
      'managerPersonalWallet': manager ?
        'separate-manager-wallet-readonly' : 'not-a-manager',
      'premiumIdentifier': active == null ?
        'active-selection-unverified' : activeId == originalId ?
        'original-id-selection-readonly' :
        'active-id-accepted-grant-and-receipt-verified-readonly',
      'weeklyLeague': week == null ?
        'week-score-unverified' : 'score-readonly-no-repeat-award',
      'earnedDiamonds': 'legacy-100340-financial-baseline-not-attested',
      'xpAndLevel': 'legacy-100340-financial-baseline-not-attested',
      'taskPoints': 'historical-award-ledger-not-attested',
      'dailyTasks': 'completion-claim-history-not-attested',
      'trafficQuestions': 'old-phone-quiz-archive-not-attested',
      'receivedGiftsAndHadaya': 'all-type-gift-receipts-not-attested',
      'premiumGrants': 'stage71-accepted-only-server-read-legacy-unknown',
      'friends': 'social-relations-not-attested',
      'savedPlaces': 'private-local-places-not-attested',
      'publishedPlaces': 'uid-place-ownership-not-attested',
      'settings': 'visual-only-is-not-all-settings',
      'historicalLeaguePrizes': 'settled-gift-receipts-not-attested',
    });
    return DedaStep2AssetsEvidence(
      accountKey: accountKey, originalId: originalId, originalUid: originalUid,
      accountName: (profile['name'] as String).trim(),
      accountType: profile['accountType'] as String,
      verifiedPaidFrameIds: Set<String>.unmodifiable(frames),
      verifiedPaidCardStyles: Set<String>.unmodifiable(paidCards),
      verifiedAcceptedPremiumIds: Set<String>.unmodifiable(acceptedPremium),
      receivedGiftWalletBalance: giftBalance,
      managerPersonalBalance: managerBalance,
      activeDisplayId: activeId,
      currentWeeklyXp: weeklyXp,
      serverSources: domains,
    );
  }
}
