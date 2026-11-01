import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'deda_100431_linked_owner_session_policy.dart';
import 'deda_lab_frame_secure_checkout.dart';
import 'deda_owned_frame_reader.dart';

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
    required this.receivedGiftWalletBalance,
    required this.managerPersonalBalance,
    required this.activeDisplayId,
    required this.currentWeeklyXp,
    required this.serverSources,
  });

  final String accountKey, originalId, originalUid;
  final String accountName, accountType;
  final Set<String> verifiedPaidFrameIds;
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
    required String weekId,
    required bool Function() isCurrent,
  }) async {
    if (!RegExp(r'^[0-9]{10,16}$').hasMatch(accountKey) ||
        !RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(originalId) ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(weekId)) {
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

    final gateway = await _read('admin_entry_access/$accountKey',
      originalUid, isCurrent);
    final gm = await _read('deda_gm_personal_diamond_wallets/$accountKey',
      originalUid, isCurrent);
    final manager = gateway?['active'] == true &&
        gateway?['status'] == 'active' &&
        gateway?['accessType'] == 'general_manager_gateway' &&
        gateway?['allowedRole'] == 'general_manager';
    int? managerBalance;
    if (manager) {
      if (gm == null || gm['accountKey'] != accountKey ||
          gm['initialBalance'] != 1000000) {
        throw const DedaStep2AssetsHold('manager-wallet-unverified');
      }
      managerBalance = _amount(gm['balance'], 'manager-wallet');
    } else if (gm != null) {
      // Do not disclose a manager wallet on an ordinary account.
      throw const DedaStep2AssetsHold('orphan-manager-wallet');
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
    }

    final leagueOwner = await _read('deda_weekly_direct_accounts/$originalId',
      originalUid, isCurrent);
    if (leagueOwner != null &&
        (leagueOwner['publicId'] != originalId ||
         leagueOwner['accountKey'] != accountKey)) {
      throw const DedaStep2AssetsHold('weekly-league-owner-conflict');
    }
    final week = await _read(
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
      'receivedGiftWallet': gift == null ?
        'wallet-absent-unknown-not-zero' : 'existing-wallet-readonly',
      'managerPersonalWallet': manager ?
        'separate-manager-wallet-readonly' : 'not-a-manager',
      'premiumIdentifier': active == null ?
        'active-selection-unverified' : 'display-selection-only-no-ownership',
      'weeklyLeague': week == null ?
        'week-score-unverified' : 'score-readonly-no-repeat-award',
      'earnedDiamonds': 'legacy-100340-financial-baseline-not-attested',
      'xpAndLevel': 'legacy-100340-financial-baseline-not-attested',
      'taskPoints': 'historical-award-ledger-not-attested',
      'dailyTasks': 'completion-claim-history-not-attested',
      'trafficQuestions': 'old-phone-quiz-archive-not-attested',
      'receivedGiftsAndHadaya': 'all-type-gift-receipts-not-attested',
      'premiumGrants': 'stage71-and-other-grants-not-fully-attested',
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
      receivedGiftWalletBalance: giftBalance,
      managerPersonalBalance: managerBalance,
      activeDisplayId: activeId,
      currentWeeklyXp: weeklyXp,
      serverSources: domains,
    );
  }
}
