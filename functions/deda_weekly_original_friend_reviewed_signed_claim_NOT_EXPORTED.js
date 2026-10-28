"use strict";
/**
 * Private bridge: original friend-accepted action -> independently reviewed,
 * HMAC-sealed task claim. NO points, XP, league scores, diamonds or payouts.
 * IMPORTANT: ALL REVIEW/CUTOVER ROWS ARE SYNTHETIC EMULATOR FIXTURES.
 * A signed QA claim never constitutes proof that an old APK stopped writing.
 */
const crypto=require("node:crypto");
const {PROJECT,ROOT:ACTION_ROOT,ISSUER:ACTION_ISSUER,
 originalClaim}=require("./deda_weekly_original_friend_accepted_action_NOT_EXPORTED.js");
const {ROOT:EPOCH_ROOT,ISSUER:EPOCH_ISSUER}=
 require("./deda_weekly_stage43_reviewed_cutover_epoch_NOT_EXPORTED.js");
const {dayInIraq}=require("./deda_weekly_xp_atomic_shadow_issuer_NOT_EXPORTED.js");
const ROOT="deda_weekly_private_friend_reviewed_signed_claims";
const REVIEW_ISSUER="private_friend_original_legacy_reviewer_fixture_only";
const CLAIM_ISSUER="private_friend_accepted_signed_claim_qa_only";
const ACCOUNT=/^[0-9]{10,16}$/,DAY=/^20\d{2}-\d\d-\d\d$/;
const HEX=/^[a-f0-9]{64}$/;
const fail=s=>{throw Error("DEDA_FRIEND_SIGNED_REVIEW_HOLD_"+s);};
const okay=n=>Number.isSafeInteger(n)&&n>=0;
const val=s=>s.exists?s.data():null;
const reviewPath=(account,key)=>
 "deda_progress_migrations/"+account+"/task_authorizations/"+key;
function guard(db,key){
 if(process.env.GCLOUD_PROJECT!==PROJECT||
    process.env.FIRESTORE_EMULATOR_HOST!=="127.0.0.1:8080"||
    process.env.DEDA_FRIEND_REVIEW_EMULATOR_ONLY!=="true"||
    typeof db?.runTransaction!=="function"||
    !Buffer.isBuffer(key)||key.length<32)fail("EMULATOR_ONLY");
}
function sealFields({accountKey,dayId,eventKey,relationId,migrationId,
   reviewerDecisionId,approvedAtMs,issuedAtMs}){
 return Object.freeze({
  format:1,issuer:CLAIM_ISSUER,emulatorOnly:true,
  canAuthorizeProduction:false,oldApkRevocationVerified:false,
  taskId:"long_trip",action:"friend_accepted",
  accountKey,dayId,eventKey,relationId,migrationId,
  reviewerDecisionId,approvedAtMs,issuedAtMs,
  pointsIfIndependentlySettled:5,
  levelXpIfIndependentlySettled:20,
  socialCoinsIfIndependentlySettled:10,
  actuallyCreditedPoints:0,actuallyCreditedXp:0,
  actuallyCreditedSocialCoins:0,actuallyCreditedLeagueXp:0,
  actuallyCreditedDiamonds:0
 });
}
function sign(key,record){
 return crypto.createHmac("sha256",key)
  .update("DEDA_PRIVATE_FRIEND_SIGNED_CLAIM_V1\n")
  .update(JSON.stringify(record)).digest("hex");
}
function timingEquals(a,b){
 if(!HEX.test(a||"")||!HEX.test(b||""))return false;
 return crypto.timingSafeEqual(Buffer.from(a,"hex"),Buffer.from(b,"hex"));
}
async function checked(reader,ctx){
 const {accountKey,dayId,eventKey,issuedAtMs}=ctx;
 if(!ACCOUNT.test(accountKey||"")||!DAY.test(dayId||"")||
    !HEX.test(eventKey||"")||!okay(issuedAtMs)||
    originalClaim(accountKey,dayId).eventKey!==eventKey)
   fail("INVALID_ORIGINAL_ACCOUNT_TASK");
 const [action,migration,epoch,review]=await Promise.all([
  reader(ACTION_ROOT+"/"+eventKey),
  reader("deda_progress_migrations/"+accountKey),
  reader(EPOCH_ROOT+"/"+accountKey),
  reader(reviewPath(accountKey,eventKey))
 ]);
 if(!action||action.issuer!==ACTION_ISSUER||action.emulatorOnly!==true||
    action.canAuthorizeProduction!==false||
    action.accountKey!==accountKey||
    action.taskId!=="long_trip"||action.approvedAction!=="friend_accepted"||
    action.dayId!==dayId||action.eventKey!==eventKey||
    action.originalLocalClaimAwarded!=="UNKNOWN_REQUIRES_MIGRATION_REVIEW"||
    action.pointsGranted!==0||action.coinsGranted!==0||
    action.xpGranted!==0||action.leagueXpGranted!==0||
    action.diamondsGranted!==0||
    !okay(action.approvedAtMs)||action.approvedAtMs>issuedAtMs||
    issuedAtMs-action.approvedAtMs>300000||
    dayInIraq(action.approvedAtMs)!==dayId||
    typeof action.originalRelationId!=="string"||
    !/^[A-Za-z0-9_-]{1,128}__[A-Za-z0-9_-]{1,128}$/.test(action.originalRelationId))
   fail("ORIGINAL_FRIEND_ACTION_NOT_VERIFIED");
 if(!migration||migration.accountKey!==accountKey||
    migration.phase!=="cutover-complete"||
    !/^[A-Za-z0-9_-]{20,80}$/.test(migration.migrationId||"")||
    !HEX.test(migration.evidenceDigest||"")||
    !HEX.test(migration.baselineEventKey||"")||
    !/^[A-Za-z0-9_-]{20,80}$/.test(migration.settlementId||""))
   fail("ORIGINAL_LEGACY_BASELINE_NOT_SETTLED");
 if(!epoch||epoch.issuer!==EPOCH_ISSUER||
    epoch.emulatorOnly!==true||epoch.canAuthorizeProduction!==false||
    epoch.realOldApkRevocationVerified!==false||
    epoch.phase!=="reviewed-server-only-private-fixture"||
    epoch.accountKey!==accountKey||
    epoch.migrationId!==migration.migrationId||
    epoch.evidenceDigest!==migration.evidenceDigest||
    epoch.baselineEventKey!==migration.baselineEventKey||
    epoch.settlementId!==migration.settlementId||
    epoch.pendingLocalClaims!==0||
    epoch.pendingPurchases!==0||epoch.pendingReservations!==0||
    !okay(epoch.effectiveAtMs)||epoch.effectiveAtMs>action.approvedAtMs||
    !okay(epoch.expiresAtMs)||epoch.expiresAtMs<=issuedAtMs)
   fail("REVIEWED_EMULATOR_CUTOVER_MISSING");
 if(!review||review.issuer!==REVIEW_ISSUER||
    review.emulatorOnly!==true||review.canAuthorizeProduction!==false||
    review.oldApkRevocationVerified!==false||
    review.accountKey!==accountKey||
    review.dayId!==dayId||review.eventKey!==eventKey||
    review.taskId!=="long_trip"||
    review.migrationId!==migration.migrationId||
    review.originalRelationId!==action.originalRelationId||
    review.reviewedClaimStatus!=="fresh_server_only_after_cutover_fixture"||
    review.originalLocalTaskPointsReconciledInFixture!==true||
    review.originalLocalXpReconciledInFixture!==true||
    review.originalLocalCoinsReconciledInFixture!==true||
    review.historicClaimAlreadyCredited!==false||
    review.pendingLegacyClaimsInFixture!==0||
    !/^[A-Za-z0-9_-]{20,80}$/.test(review.reviewerDecisionId||"")||
    !okay(review.reviewedAtMs)||
    review.reviewedAtMs>issuedAtMs)
   fail("INDEPENDENT_LEGACY_CLAIM_REVIEW_REQUIRED");
 return sealFields({...ctx,relationId:action.originalRelationId,
  migrationId:migration.migrationId,
  reviewerDecisionId:review.reviewerDecisionId,
  approvedAtMs:action.approvedAtMs});
}
async function issuePrivateReviewedFriendClaim({
 db,backendSecret,accountKey,dayId,eventKey,serverNowMs
}){
 guard(db,backendSecret);
 const ref=db.doc(ROOT+"/"+eventKey);
 return db.runTransaction(async tx=>{
  const reader=async path=>val(await tx.get(db.doc(path)));
  // Existing claims validate at original issue clock, but CURRENT
  // action/reviewer/cutover evidence must still match on every retry.
  const previous=await tx.get(ref);
  const issueClock=previous.exists?
    previous.data()?.record?.issuedAtMs:serverNowMs;
  if(!okay(issueClock)||!okay(serverNowMs)||
     issueClock>serverNowMs||serverNowMs-issueClock>7*86400000)
   fail("EXPIRED_OR_INVALID_REPLAY");
  const record=await checked(reader,{
    accountKey,dayId,eventKey,issuedAtMs:issueClock
  });
  const signature=sign(backendSecret,record);
  if(previous.exists){
   const old=previous.data();
   if(old?.emulatorOnly!==true||
      old?.canAuthorizeProduction!==false||
      old?.signature!==signature||
      JSON.stringify(old.record)!==JSON.stringify(record))
     fail("SIGNED_CLAIM_REPLAY_TAMPERED");
   return Object.freeze({outcome:"already_signed",created:0,
    actuallyCreditedXp:0,actuallyCreditedLeagueXp:0,
    actuallyCreditedDiamonds:0,emulatorOnly:true});
  }
  tx.create(ref,{emulatorOnly:true,canAuthorizeProduction:false,
    record,signature});
  return Object.freeze({outcome:"private_reviewed_claim_signed",created:1,
   actuallyCreditedXp:0,actuallyCreditedLeagueXp:0,
   actuallyCreditedDiamonds:0,emulatorOnly:true});
 });
}
async function validatePrivateReviewedFriendClaim({
 db,backendSecret,accountKey,dayId,eventKey,serverNowMs
}){
 guard(db,backendSecret);
 if(!okay(serverNowMs))fail("INVALID_VALIDATION_CLOCK");
 return db.runTransaction(async tx=>{
  const reader=async path=>val(await tx.get(db.doc(path)));
  const stored=await reader(ROOT+"/"+eventKey);
  const issuedAtMs=stored?.record?.issuedAtMs;
  if(!okay(issuedAtMs)||issuedAtMs>serverNowMs||
     serverNowMs-issuedAtMs>300000)
   fail("SIGNATURE_EXPIRED_REQUIRES_HISTORICAL_REVIEW");
  const record=await checked(reader,{accountKey,dayId,eventKey,
    issuedAtMs});
  const digest=sign(backendSecret,record);
  if(stored.emulatorOnly!==true||
     stored.canAuthorizeProduction!==false||
     !timingEquals(stored.signature,digest)||
     JSON.stringify(record)!==JSON.stringify(stored.record))
   fail("SIGNED_FRIEND_REVIEW_INVALID");
  return Object.freeze({readOnly:true,emulatorOnly:true,
    independentlyReviewedFixture:true,canAuthorizeProduction:false,
    canCreditXp:false,canCreditLeague:false,canCreditDiamonds:false,
    eventKey});
 });
}
module.exports=Object.freeze({PROJECT,ROOT,REVIEW_ISSUER,CLAIM_ISSUER,
 reviewPath,sealFields,sign,issuePrivateReviewedFriendClaim,
 validatePrivateReviewedFriendClaim});
