import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_step2_completion_gate.dart';
import 'package:d_iraq_ludo/deda_step2_recovery_guardian.dart';
import 'package:d_iraq_ludo/deda_step2_assets_readback.dart';
import 'package:d_iraq_ludo/deda_step2_account_domains_recovery_readback.dart';

const uid='original-owner-uid';
const original='@DEDA-ABC123';
const account='07712345678';

DedaStep2AssetsEvidence assets({int? gift=500,
    String id=original, String current=uid, String? active='@DEDA-AB1234',
    int? weekly=120}) => DedaStep2AssetsEvidence(
  accountKey:account,originalId:id,originalUid:current,
  accountName:'Owner',accountType:'user',
  verifiedPaidFrameIds: const {'FRAME_03'},
  verifiedPaidCardStyles: const {'gold'},
  verifiedAcceptedPremiumIds: const {'@DEDA-AB1234'},
  receivedGiftWalletBalance:gift,managerPersonalBalance:null,
  activeDisplayId:active,currentWeeklyXp:weekly,serverSources:const {},
);

DedaAccountDomainContinuity domains({int? gift=500,
    String? active='@DEDA-AB1234', int? weekly=120}) =>
  DedaAccountDomainContinuity(
  status:const {},friendRelations:2,acceptedFriends:2,giftReceipts:3,
  iraqDay:'2026-11-05',existingGiftWallet:gift,
  existingWeeklyXp:weekly,activeDisplayId:active,
);

const guardian=DedaVaultRecoveryResult(stepStates:{
  DedaVaultCode.levelPointsRestore:DedaVaultStepState.verified,
  DedaVaultCode.publishedPlaceRecovery:DedaVaultStepState.verified,
},stoppedSafely:false);

void main() {
  test('verified records remain observations, never new money or complete cutover', () {
    final report=DedaStep2CompletionGate.assess(originalUid:uid,
      originalId:original,recovery:guardian,domainReadback:domains(),
      assetReadback:assets(),freeAppearanceHydrated:true,quizUiHydrated:true);
    expect(report.domains['giftDiamondWallet'],
      DedaStep2CompletionState.verifiedExistingSource);
    expect(report.domains['paidFrames'],
      DedaStep2CompletionState.verifiedExistingSource);
    expect(report.domains['levelPoints'],
      DedaStep2CompletionState.restoredAndReadback);
    expect(report.domains['earnedAdDiamonds'],
      DedaStep2CompletionState.missingHistoricalProof);
    expect(report.domains['historicalLeaguePrizeClaims'],
      DedaStep2CompletionState.missingHistoricalProof);
    expect(report.canIssueFinancialRewards,false);
    expect(report.canDeleteOldPhoneData,false);
    expect(report.canPrepareFullRecoveryApk,false);
    expect(report.allDomainsRestored,false);
    expect(report.domains.length,23);
  });

  test('different server wallet amounts fail closed rather than add/overwrite', () {
    final report=DedaStep2CompletionGate.assess(originalUid:uid,
      originalId:original,recovery:guardian,domainReadback:domains(gift:501),
      assetReadback:assets(gift:500));
    expect(report.hasConflict,true);
    expect(report.domains['giftDiamondWallet'],DedaStep2CompletionState.needsReview);
  });

  test('cross-UID paid receipts invalidate all owned evidence', () {
    final report=DedaStep2CompletionGate.assess(originalUid:uid,
      originalId:original,recovery:guardian,domainReadback:domains(),
      assetReadback:assets(current:'foreign-uid'));
    expect(report.hasConflict,true);
    expect(report.domains['originalOwnerUid'],DedaStep2CompletionState.needsReview);
    expect(report.domains['paidFrames'],DedaStep2CompletionState.needsReview);
    expect(report.domains['acceptedPremiumIds'],DedaStep2CompletionState.needsReview);
  });

  test('active ID and weekly score disagreement is detected independently', () {
    final report=DedaStep2CompletionGate.assess(originalUid:uid,
      originalId:original,recovery:guardian,domainReadback:domains(
        active:'@DEDA-AC1234',weekly:121),assetReadback:assets());
    expect(report.domains['activePremiumId'],DedaStep2CompletionState.needsReview);
    expect(report.domains['currentLeaguePoints'],DedaStep2CompletionState.needsReview);
  });

  test('missing cloud source means pending, never empty, zero or a grant', () {
    final r=DedaStep2CompletionGate.assess(
      originalUid:uid,originalId:original);
    expect(r.domains['giftDiamondWallet'],
      DedaStep2CompletionState.missingHistoricalProof);
    expect(r.domains['originalOwnerUid'],DedaStep2CompletionState.notRun);
    expect(r.allDomainsRestored,false);
    expect(r.canPrepareFullRecoveryApk,false);
  });

  test('guardian blocked makes owner proof not-run; no restored UI by omission', () {
    const blocked=DedaVaultRecoveryResult(stepStates:{},
      stoppedSafely:true);
    final r=DedaStep2CompletionGate.assess(
      originalUid:uid,originalId:original,
      recovery:blocked,assetReadback:assets());
    expect(r.domains['originalOwnerUid'],DedaStep2CompletionState.notRun);
    expect(r.domains['levelPoints'],
      DedaStep2CompletionState.missingHistoricalProof);
    expect(r.allDomainsRestored,false);
  });

  test('completion evidence map cannot be mutated by a caller', () {
    final r=DedaStep2CompletionGate.assess(originalUid:uid,
        originalId:original);
    expect(() => r.domains['earnedAdDiamonds'] =
      DedaStep2CompletionState.restoredAndReadback,throwsUnsupportedError);
  });
}
