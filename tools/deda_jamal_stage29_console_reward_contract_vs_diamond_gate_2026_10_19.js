"use strict";

/**
 * Stage29 — owner AdMob CONSOLE SCREENSHOT vs DEDA source reconciliation.
 *
 * Screenshot 2026-10-19: ONE rewarded unit, name "DEDA Rewarded +5 Points",
 * reward settings "5 DEDA Points", SSV "No callback URL provided".
 * These are UI observations, NOT a Google-signed provider callback or the
 * latest official Google documentation. NEVER infer 3 diamond reward rights.
 *
 * No network/SDK, Firebase writes, wallet migration, real ads or deployment.
 */
const {detectSourceReadiness,loadRepoSources}=
  require("./deda_jamal_stage28_real_admob_unit_and_legacy_ads_readonly_audit_2026_10_19.js");

const CONSOLE_SNAPSHOT=Object.freeze({
  capturedDate:"2026-10-19",
  source:"OWNER_ADMOB_UI_SCREENSHOT_READ_ONLY_NOT_SIGNED",
  adUnitName:"DEDA Rewarded +5 Points",
  adFormat:"Rewarded",
  adUnitId:"ca-app-pub-2512641627784244/6037567292",
  rewardAmount:5,
  rewardItem:"DEDA Points",
  ssvCallbackConfigured:false,
  callbackUi:"No callback URL provided",
});
const DEMO_EXPECTED=Object.freeze({
  rewardAmount:1,
  rewardItem:"diamonds",
  userVisibleAwardDiamonds:3,
  isRealGoogleCallback:false,
});
function fail(reason){
  const error=new Error(reason);error.code="failed-precondition";throw error;
}
function reviewConsoleVsCurrentSource({
  sourceReview=detectSourceReadiness(loadRepoSources()),
  consoleSnapshot=CONSOLE_SNAPSHOT,
}={}){
  if(!sourceReview||sourceReview.sourceEvidenceConsistent!==true ||
      !sourceReview.config||!consoleSnapshot ||
      consoleSnapshot.source!==CONSOLE_SNAPSHOT.source ||
      consoleSnapshot.capturedDate!==CONSOLE_SNAPSHOT.capturedDate ||
      consoleSnapshot.adUnitId!==CONSOLE_SNAPSHOT.adUnitId ||
      consoleSnapshot.adUnitName!==CONSOLE_SNAPSHOT.adUnitName ||
      consoleSnapshot.adFormat!=="Rewarded" ||
      consoleSnapshot.rewardAmount!==5 ||
      consoleSnapshot.rewardItem!=="DEDA Points" ||
      consoleSnapshot.callbackUi!=="No callback URL provided" ||
      consoleSnapshot.ssvCallbackConfigured!==false) {
    fail("owner-console-screen-recheck-required-no-trust-in-submitted-settings");
  }
  if(sourceReview.config.realAdUnitId!==consoleSnapshot.adUnitId){
    fail("code-vs-console-ad-unit-id-mismatch-stop-before-config-change");
  }
  const incompatible=Object.freeze({
    sameAdUnitAsStagedDemo:sourceReview.config.realAdUnitId===
      consoleSnapshot.adUnitId,
    serverCallbackAbsent:consoleSnapshot.ssvCallbackConfigured===false,
    recordedRewardAmountDiffersFromStage22Demo:
      consoleSnapshot.rewardAmount!==DEMO_EXPECTED.rewardAmount,
    recordedRewardItemDiffersFromStage22Demo:
      consoleSnapshot.rewardItem!==DEMO_EXPECTED.rewardItem,
    historicClientAwardIsThreeDiamonds:
      sourceReview.checks.diamondsAreThreePerAd,
    independentFivePointTaskRewardCodePresent:
      sourceReview.checks.separateTaskRewardIsPoints,
    currentStage22RewardItemParserNeedsReviewedAdaptation:
      !/^[A-Za-z0-9_-]{1,60}$/.test(consoleSnapshot.rewardItem),
  });
  return Object.freeze({
    stage:29,
    observedConsole:CONSOLE_SNAPSHOT,
    demoContract:DEMO_EXPECTED,
    mismatch:Object.freeze(incompatible),
    conclusion:"CONSOLE_5_DEDA_POINTS_NOT_STAGE22_DEMO_1_DIAMONDS",
    status:"OWNER_OBSERVED_SETTINGS_NO_CALLBACK_REQUIRES_REAL_GOOGLE_SSV",
    // Do NOT use fake data to claim real rewards or implement exchange rates.
    currentAppRewardsMustRemainUnchanged:true,
    oldLocalDiamondsPreserved:true,
    localTaskPointsPreserved:true,
    migrateOrConvertPointsToDiamonds:false,
    repriceOldBalances:false,
    createNewAdUnitAutomatically:false,
    modifyExistingRewardedUnitAutomatically:false,
    officialGoogleSSVVerified:false,
    googleCallbackOriginProven:false,
    liveRewardGrantAllowed:false,
    liveDiamondCheckoutAllowed:false,
    nextGate:"OWNER_APPROVED_DISTINCT_REWARD_POLICY_AND_OFFICIAL_GOOGLE_SSV",
  });
}
/**
 * A signed event can only be accepted by a verified server implementation,
 * after owner approval of an exact reward unit and its intended economy.
 * This utility is a RED LIGHT, not a callable or reward payment.
 */
function prohibitProductionRewardAction(intent,report){
  if(typeof intent!=="string"||
      !["grant_points","grant_diamonds","spend_diamonds",
        "assign_real_google_provenance","enable_ssv"].includes(intent)){
    fail("unknown-real-reward-action-denied");
  }
  if(!report || report.officialGoogleSSVVerified!==false ||
      report.liveRewardGrantAllowed!==false ||
      report.liveDiamondCheckoutAllowed!==false ||
      report.observedConsole?.ssvCallbackConfigured!==false){
    fail("unreviewed-live-ssv-state-denied");
  }
  fail("ssv-not-configured-5-points-is-not-3-diamonds");
}
module.exports={
  CONSOLE_SNAPSHOT,DEMO_EXPECTED,reviewConsoleVsCurrentSource,
  prohibitProductionRewardAction,
};
