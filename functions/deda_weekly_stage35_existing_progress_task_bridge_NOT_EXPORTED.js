"use strict";
/**
 * STAGE35: read-only compatibility of a private Stage34 fixture receipt with
 * DEDA's EXISTING, UNDEPLOYED progress_archive/reconcile-core.cjs vector.
 *
 * No new wallet or real XP issuer. Does not write Firestore, open a client
 * API, reconcile original phone XP or authorize actual weekly rank/payout.
 * A future trusted server must prove old-writer fencing, approved migration,
 * original task completion and exact claim before adapting this projection.
 */
const core=require("../tools/app_stability/progress_archive/reconcile-core.cjs");
const {clockState}=require(
  "./deda_weekly_stage31_frozen_league_winner_card_NOT_EXPORTED.js");
const {dayInIraq}=require(
  "./deda_weekly_xp_atomic_shadow_issuer_NOT_EXPORTED.js");
const {opaqueReceiptId}=require(
  "./deda_weekly_owner_receipt_gate_NOT_EXPORTED.js");
const ACCOUNT=/^[0-9]{10,16}$/;
const DAY=/^20\d{2}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$/;
const FINGERPRINT=/^[a-f0-9]{64}$/;
const FIELDS=Object.freeze([
  "emulatorOnly","issuer","accountKey","taskId","dayId",
  "receiptId","amount","verifiedAtMs","createdAtMs","weekId",
  "competitionStatus"
]);
function fail(message){throw Error("DEDA_STAGE35_COMPATIBILITY_BLOCK_"+message);}
function validInt(n){return Number.isSafeInteger(n)&&n>=0;}
function exact(x){
  return x&&typeof x==="object"&&!Array.isArray(x)&&
    Object.keys(x).length===FIELDS.length&&
    FIELDS.every(k=>Object.hasOwn(x,k));
}
function previewTaskClaimForExistingProgress({shadowReceipt,firstOpenMs,
  reviewedCutoverFixture,requestedAccountKey}){
  if(!exact(shadowReceipt)||shadowReceipt.emulatorOnly!==true||
     shadowReceipt.issuer!=="stage34_atomic_level_fixture_v1"||
     !ACCOUNT.test(shadowReceipt.accountKey||"")||
     shadowReceipt.accountKey!==requestedAccountKey||
     shadowReceipt.taskId!=="share_personal_location"||
     !DAY.test(shadowReceipt.dayId||"")||
     !FINGERPRINT.test(shadowReceipt.receiptId||"")||
     shadowReceipt.amount!==20||
     !validInt(shadowReceipt.verifiedAtMs)||
     !validInt(shadowReceipt.createdAtMs)||
     shadowReceipt.verifiedAtMs>shadowReceipt.createdAtMs||
     dayInIraq(shadowReceipt.verifiedAtMs)!==shadowReceipt.dayId||
     shadowReceipt.receiptId!==opaqueReceiptId({
       accountKey:shadowReceipt.accountKey,
       dayId:shadowReceipt.dayId,taskId:shadowReceipt.taskId
     }))fail("original_shadow_receipt_not_verified");
  // This flag is a LOCAL QA fixture, NOT actual manager approval or
  // proof the old local APK was fenced. No production caller exists.
  const approved=reviewedCutoverFixture;
  if(!approved||approved.emulatorOnly!==true||
     approved.canAuthorizeLiveWrites!==false||
     approved.accountKey!==requestedAccountKey||
     approved.cutoverPhase!=="reviewed_fixture_only"||
     approved.originalLocalSourcePreserved!==true||
     approved.protectedWriterFenceModelled!==true)
    fail("historic_progress_review_not_proven");
  const clock=clockState({
    firstOpenMs,serverNowMs:shadowReceipt.createdAtMs});
  const hasLeaguePoints=clock.phase==="active";
  const expectedWeek=hasLeaguePoints?clock.current?.weekId:null;
  if(shadowReceipt.weekId!==expectedWeek||
     shadowReceipt.competitionStatus!==
       (hasLeaguePoints?"league":"frozen"))
    fail("league_phase_or_week_mismatch");
  const progressReceipt=core.parseReceipt({
    format:1,accountKey:shadowReceipt.accountKey,
    source:"task-claim-v1",
    // Deterministic account/day/task identity survives phone or UID change.
    sourceId:"daily-task|"+shadowReceipt.dayId+"|"+shadowReceipt.taskId,
    kind:"award",
    // +5 ordinary task points, +20 earned LEVEL XP. Login and traffic
    // question points are separate; coins/diamonds must stay unchanged.
    delta:{points:5,coins:0,xp:20,earnedDiamonds:0}
  },shadowReceipt.accountKey);
  return Object.freeze({
    privateCompatibilityPreviewOnly:true,canWriteRealProgress:false,
    canPublishLeague:false,canGrantDiamonds:false,
    existingProgressPath:"deda_verified_progress",
    existingReceiptSource:"task-claim-v1",
    eventKey:core.eventKey(progressReceipt),progressReceipt,
    leagueWeekId:expectedWeek,eligibleLeagueXp:hasLeaguePoints?20:0,
  });
}
module.exports=Object.freeze({previewTaskClaimForExistingProgress});
