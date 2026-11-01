import 'package:firebase_auth/firebase_auth.dart';

import 'deda_step2_assets_readback.dart';
import 'deda_step2_friendship_readback.dart';
import 'deda_step2_linked_published_place_recovery.dart';

/// DEDA step 2: single read-only full-account inventory before allowing any
/// device cutover. This IS NOT a migration or an approval to pay, restore
/// balance/XP, reissue gifts, relink old UID, or reassign published map places.
const bool dedaStep2FullAccountPreflightEnabled = bool.fromEnvironment(
  'DEDA_STEP2_FULL_ACCOUNT_PREFLIGHT', defaultValue: false);

class DedaStep2FullAccountPreflightHold implements Exception {
  const DedaStep2FullAccountPreflightHold(this.reason);
  final String reason;
  @override
  String toString() => 'DedaStep2FullAccountPreflightHold($reason)';
}

/// Source inspection is explicitly distinct from completed restoration.
enum DedaStep2SourceStatus {
  sourceInspected,
  notAttested,
  notApplicable,
}

class DedaStep2AccountDomain {
  const DedaStep2AccountDomain(this.status, this.reason);
  final DedaStep2SourceStatus status;
  final String reason;
}

/// These are ALL the account areas reviewed for old 100340 users. Missing a
/// field from a future audit must add to this exhaustive list, never silently
/// be classified as restored.
const dedaStep2FullAccountDomains = <String>[
  'profile',
  'originalId',
  'levelAndXp',
  'taskPoints',
  'earnedAndPurchasedDiamonds',
  'giftWallet',
  'managerWallet',
  'paidFrames',
  'premiumIdentifierOwnership',
  'activePremiumIdentifier',
  'giftInboxAndPending',
  'dailyTaskProgress',
  'trafficQuizProgress',
  'currentLeague',
  'historicalLeaguePrizes',
  'friends',
  'publishedPlace',
  'pendingPlaceEdits',
  'savedPrivatePlaces',
  'avatarAndBackground',
  'otherSettings',
  'purchaseAndRewardReceipts',
  'accountRecoveryAndPinSecurity',
];

class DedaStep2FullAccountInventory {
  const DedaStep2FullAccountInventory({
    required this.accountKey,
    required this.originalUid,
    required this.originalId,
    required this.accountName,
    required this.accountType,
    required this.serverFriendCount,
    required this.serverOwnedFrameCount,
    required this.confirmedPlaceId,
    required this.domains,
  });

  final String accountKey, originalUid, originalId;
  final String accountName, accountType;
  final int serverFriendCount, serverOwnedFrameCount;
  final String? confirmedPlaceId;
  final Map<String, DedaStep2AccountDomain> domains;

  List<String> get notAttestedDomains => List.unmodifiable([
    for (final field in dedaStep2FullAccountDomains)
      if (domains[field]?.status == DedaStep2SourceStatus.notAttested)
        field,
  ]);

  /// Source inspection never authorizes a complete migration. An old
  /// handset must remain intact until every domain is settled by trusted
  /// reconciliation, PIN rate-limiting, release rules and two-device QA.
  bool get allAccountDataRestored => false;
  bool get allowPhoneCutover => false;
  bool get canRestoreFinancialValue => false;
  bool get canReissueAwards => false;
  bool get canTransferMapOwnership => false;
  bool get canEraseOriginalPhoneData => false;
}

class DedaStep2FullAccountPreflight {
  const DedaStep2FullAccountPreflight({
    required this.assets,
    required this.friends,
    required this.places,
    required this.currentUid,
    this.enabled = dedaStep2FullAccountPreflightEnabled,
  });

  factory DedaStep2FullAccountPreflight.firebase() =>
      DedaStep2FullAccountPreflight(
        assets: DedaStep2AssetsReadback.firebase(),
        friends: DedaStep2FriendshipReadback.firebase(),
        places: const DedaStep2FirebaseLinkedPlaceIo(),
        currentUid: () => FirebaseAuth.instance.currentUser?.uid,
      );

  final DedaStep2AssetsReadback assets;
  final DedaStep2FriendshipReadback friends;
  final DedaStep2LinkedPlaceIo places;
  final String? Function() currentUid;
  final bool enabled;

  void _check(String uid, bool Function() isCurrent) {
    if (!enabled || !assets.enabled || !friends.enabled ||
        uid.trim().isEmpty || currentUid() != uid || !isCurrent()) {
      throw const DedaStep2FullAccountPreflightHold(
          'original-account-preflight-disabled-or-session-changed');
    }
  }

  Future<DedaStep2FullAccountInventory> inspect({
    required String accountKey,
    required String originalUid,
    required String originalId,
    required String currentWeekId,
    required bool Function() isCurrent,
  }) async {
    void check() => _check(originalUid, isCurrent);
    check();
    // Both data services independently check verified original identity,
    // refuse cached/pending writes and use immutable original personal ID.
    final assetsEvidence = await assets.inspect(
      accountKey: accountKey, originalId: originalId,
      originalUid: originalUid, weekId: currentWeekId,
      isCurrent: isCurrent,
    );
    check();
    final friendsEvidence = await friends.inspect(
      accountKey: accountKey, originalUid: originalUid,
      originalId: originalId, isCurrent: isCurrent,
    );
    check();
    if (assetsEvidence.accountKey != accountKey ||
        assetsEvidence.originalUid != originalUid ||
        assetsEvidence.originalId != originalId ||
        friendsEvidence.accountKey != accountKey ||
        friendsEvidence.originalUid != originalUid ||
        friendsEvidence.originalId != originalId) {
      throw const DedaStep2FullAccountPreflightHold(
          'cross-domain-account-identity-mismatch');
    }
    if (assetsEvidence.fullAccountRestored ||
        assetsEvidence.canRestoreDiamonds ||
        friendsEvidence.allAccountDataRestored ||
        friendsEvidence.canCreateMissingFriendships) {
      throw const DedaStep2FullAccountPreflightHold(
          'source-evidence-must-not-authorize-recovery');
    }

    String? placeId;
    String placeReason = 'not-a-place-owner';
    if (assetsEvidence.accountType == 'placeOwner') {
      // Read-only owner-place verification. Calling
      // recoverOriginalPublishedPlace() here would mutate local state,
      // so the audit intentionally uses ONLY the server query interface.
      final result = await places.publishedForAccount(accountKey);
      check();
      if (result.fromCache || result.pendingWrites ||
          result.documents.length != 1) {
        placeReason = 'published-place-missing-ambiguous-or-not-from-server';
      } else {
        final row = result.documents.single;
        final place = row.fields;
        final approval = place['approvalNumber'];
        if (row.fromCache || row.pendingWrites ||
            row.id.trim().isEmpty || row.id.contains('/') ||
            place['accountKey'] != accountKey ||
            place['ownerUid'] != originalUid ||
            place['published'] != true ||
            approval is! String || approval.trim().isEmpty) {
          placeReason = 'published-place-owner-or-approval-unverified';
        } else {
          placeId = row.id;
          placeReason = 'original-uid-and-approval-source-verified';
        }
      }
    }
    check();

    DedaStep2AccountDomain found(String reason) =>
        DedaStep2AccountDomain(DedaStep2SourceStatus.sourceInspected, reason);
    DedaStep2AccountDomain missing(String reason) =>
        DedaStep2AccountDomain(DedaStep2SourceStatus.notAttested, reason);
    DedaStep2AccountDomain na(String reason) =>
        DedaStep2AccountDomain(DedaStep2SourceStatus.notApplicable, reason);

    final recorded = <String, DedaStep2AccountDomain>{
      'profile': found('server-profile-same-original-uid'),
      'originalId': found('immutable-original-personal-id-route'),
      'levelAndXp': missing('authoritative-legacy-level-xp-ledger-required'),
      'taskPoints': missing('historical-task-claims-ledger-required'),
      'earnedAndPurchasedDiamonds':
          missing('authoritative-diamond-purchase-and-earning-ledger-required'),
      'giftWallet': assetsEvidence.receivedGiftWalletBalance == null
          ? missing('wallet-absent-unknown-not-zero')
          : found('received-gift-wallet-only-not-total-diamonds'),
      'managerWallet': assetsEvidence.managerPersonalBalance != null
          ? found('separate-verified-manager-pool-no-transfers')
          : na('no-manager-balance-reported'),
      'paidFrames': found('strict-paid-receipt-source-only'),
      'premiumIdentifierOwnership':
          missing('premium-grant-and-purchase-receipts-required'),
      'activePremiumIdentifier': assetsEvidence.activeDisplayId == null
          ? missing('active-selection-not-confirmed')
          : found('display-selection-not-ownership'),
      'giftInboxAndPending':
          missing('pending-gift-claims-and-received-history-unverified'),
      'dailyTaskProgress': missing('daily-completion-history-unverified'),
      'trafficQuizProgress':
          missing('old-phone-all-quiz-days-and-answer-history-unverified'),
      'currentLeague': assetsEvidence.currentWeeklyXp == null
          ? missing('current-week-score-not-found-unknown')
          : found('same-original-id-current-week-read-only'),
      'historicalLeaguePrizes':
          missing('settled-weekly-prize-receipts-unverified'),
      'friends': found(
          'same-uid-server-relations-only-old-deleted-uid-history-unknown'),
      'publishedPlace': assetsEvidence.accountType == 'placeOwner'
          ? (placeId == null ? missing(placeReason) : found(placeReason))
          : na(placeReason),
      'pendingPlaceEdits': assetsEvidence.accountType == 'placeOwner'
          ? missing('original-phone-edit-drafts-not-replayed-or-compared')
          : na('not-a-place-owner'),
      'savedPrivatePlaces':
          missing('legacy-unscoped-personal-place-key-not-owner-proven'),
      'avatarAndBackground':
          missing('visual-state-not-yet-full-account-migrated'),
      'otherSettings': missing('all-preferences-not-attested'),
      'purchaseAndRewardReceipts':
          missing('legacy-100340-reconciliation-and-idempotency-not-proven'),
      'accountRecoveryAndPinSecurity':
          missing('pin-rate-limit-and-two-real-phones-not-proven'),
    };
    if (recorded.length != dedaStep2FullAccountDomains.length ||
        !dedaStep2FullAccountDomains.every(recorded.containsKey)) {
      throw const DedaStep2FullAccountPreflightHold(
          'incomplete-account-domain-catalog');
    }
    return DedaStep2FullAccountInventory(
      accountKey: accountKey,
      originalUid: originalUid,
      originalId: originalId,
      accountName: assetsEvidence.accountName,
      accountType: assetsEvidence.accountType,
      serverFriendCount: friendsEvidence.relations.length,
      serverOwnedFrameCount: assetsEvidence.verifiedPaidFrameIds.length,
      confirmedPlaceId: placeId,
      domains: Map.unmodifiable(recorded),
    );
  }
}
