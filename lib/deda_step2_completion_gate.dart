import 'deda_step2_account_domains_recovery_readback.dart';
import 'deda_step2_assets_readback.dart';
import 'deda_step2_diamond_reconciliation_readonly.dart';
import 'deda_step2_recovery_guardian.dart';

/// One read-only report across the existing 12-code guardian. The guardian
/// never credits diamonds, grants items or repeats awards. A complete-looking
/// widget is not an account-completion receipt.
enum DedaStep2CompletionState {
  verifiedExistingSource,
  restoredAndReadback,
  missingHistoricalProof,
  notRun,
  needsReview,
}

class DedaStep2CompletionReport {
  const DedaStep2CompletionReport(this.domains);
  final Map<String, DedaStep2CompletionState> domains;
  bool get hasConflict =>
      domains.values.contains(DedaStep2CompletionState.needsReview);
  bool get allDomainsRestored =>
      domains.isNotEmpty && domains.values.every(
        (state) => state == DedaStep2CompletionState.restoredAndReadback);
  // Even full local/source coverage is not approval to bypass audited live
  // rules, old-100340 writer fencing and real two-phone QA.
  bool get canIssueFinancialRewards => false;
  bool get canDeleteOldPhoneData => false;
  bool get canPrepareFullRecoveryApk => false;
}

/// Pure evidence aggregation. It accepts no user-supplied balance, selected
/// premium ID, or local screenshot as authority. Existing sources are only
/// observed; the historical data gaps are not "empty" or zero.
class DedaStep2CompletionGate {
  const DedaStep2CompletionGate._();

  static DedaStep2CompletionReport assess({
    required String originalUid,
    required String originalId,
    DedaVaultRecoveryResult? recovery,
    DedaAccountDomainContinuity? domainReadback,
    DedaStep2AssetsEvidence? assetReadback,
    DedaStep2DiamondReconciliation? diamondReadback,
    bool freeAppearanceHydrated = false,
    bool quizUiHydrated = false,
  }) {
    const observed = DedaStep2CompletionState.verifiedExistingSource;
    const restored = DedaStep2CompletionState.restoredAndReadback;
    const hold = DedaStep2CompletionState.missingHistoricalProof;
    const notRun = DedaStep2CompletionState.notRun;
    const conflict = DedaStep2CompletionState.needsReview;

    final guardPassed = recovery != null && !recovery.stoppedSafely;
    final levelRestored = guardPassed &&
        recovery.stepStates[DedaVaultCode.levelPointsRestore] ==
            DedaVaultStepState.verified;
    final publishedPlaceRestored = guardPassed &&
        recovery.stepStates[DedaVaultCode.publishedPlaceRecovery] ==
            DedaVaultStepState.verified;

    final ownerMismatch = assetReadback != null &&
        (assetReadback.originalId != originalId ||
         assetReadback.originalUid != originalUid);
    final walletMismatch = assetReadback != null &&
        domainReadback?.existingGiftWallet != null &&
        assetReadback.receivedGiftWalletBalance != null &&
        domainReadback!.existingGiftWallet !=
            assetReadback.receivedGiftWalletBalance;
    // A fresh diamond inspection compares the already-existing wallet from
    // two independent Stage2 source readers. A missing snapshot must not be
    // promoted to zero or to a newly minted/replayed gift.
    final diamondOwnerMismatch = diamondReadback != null &&
        (diamondReadback.accountKey.isEmpty ||
         diamondReadback.originalId != originalId ||
         diamondReadback.originalUid != originalUid ||
         (assetReadback != null &&
          diamondReadback.accountKey != assetReadback.accountKey));
    final diamondWalletMismatch = diamondReadback != null &&
        ((domainReadback?.existingGiftWallet != null &&
          diamondReadback.receivedGiftWalletBalance !=
              domainReadback!.existingGiftWallet) ||
         (assetReadback?.receivedGiftWalletBalance != null &&
          diamondReadback.receivedGiftWalletBalance !=
              assetReadback!.receivedGiftWalletBalance));
    final activeMismatch = assetReadback != null &&
        domainReadback?.activeDisplayId != null &&
        assetReadback.activeDisplayId != null &&
        domainReadback!.activeDisplayId != assetReadback.activeDisplayId;
    final weeklyMismatch = assetReadback != null &&
        domainReadback?.existingWeeklyXp != null &&
        assetReadback.currentWeeklyXp != null &&
        domainReadback!.existingWeeklyXp != assetReadback.currentWeeklyXp;

    final identityState = ownerMismatch ? conflict :
        guardPassed ? observed : notRun;
    final walletState = walletMismatch || ownerMismatch ||
        diamondOwnerMismatch || diamondWalletMismatch ? conflict :
        domainReadback?.existingGiftWallet != null &&
                assetReadback?.receivedGiftWalletBalance != null
            ? observed : hold;
    final activeState = activeMismatch || ownerMismatch ? conflict :
        assetReadback?.activeDisplayId != null &&
                domainReadback?.activeDisplayId != null
            ? observed : hold;

    final states = <String,DedaStep2CompletionState>{
      'originalOwnerUid': identityState,
      'giftDiamondWallet': walletState,
      'earnedAdDiamonds': hold, // Legacy on-device, unsigned 100340 source.
      // Gross receipts and local 100340 ads cannot establish a complete
      // earned-minus-spent transaction ledger. Do not unlock finances.
      'diamondSpendAndAwardLedger':
          diamondOwnerMismatch || diamondWalletMismatch ? conflict : hold,
      'managerPersonalAndAdminSeparation': hold,
      'paidFrames': assetReadback == null ? notRun : observed,
      'paidIdCards': assetReadback == null ? notRun : observed,
      'acceptedPremiumIds': assetReadback == null ? notRun : observed,
      'activePremiumId': activeState,
      'giftInboxAndHadaya': domainReadback == null ? notRun :
        domainReadback.giftReceipts > 0 ? observed : hold,
      'historicalLeaguePrizeClaims': domainReadback != null &&
        domainReadback.weeklyPrizeReceipts > 0 ? observed : hold,
      'currentLeaguePoints': weeklyMismatch ? conflict :
        domainReadback?.existingWeeklyXp != null ? observed : hold,
      'levelPoints': levelRestored ? restored : hold,
      'dailyTaskClaimLedger': hold,
      'historicalTrafficQuestions': hold,
      'friends': domainReadback == null ? notRun :
        domainReadback.friendRelations > 0 ? observed : hold,
      'publishedPlace': publishedPlaceRestored ? restored : hold,
      'savedPlacesAndFavorites': hold,
      'freeAppearance': freeAppearanceHydrated ? restored : hold,
      'allSettings': hold,
      'quizUiToday': quizUiHydrated ? restored : hold,
      'legacy100340WriteFence': hold,
      'liveFirebaseAndTwoPhoneApproval': hold,
    };
    if (ownerMismatch || diamondOwnerMismatch) {
      for (final item in ['paidFrames','paidIdCards','acceptedPremiumIds']) {
        states[item] = conflict;
      }
    }
    return DedaStep2CompletionReport(Map.unmodifiable(states));
  }
}
