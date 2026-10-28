"use strict";
/**
 * Stage: accepted original DEDA friend -> signed independently-reviewed
 * task proof -> atomic PRIVATE candidate weekly XP EVENT + per-account TALLY.
 *
 * NOT a credit to original XP, coins, points, user wallet or DEDA league.
 * All reviewer/cutover data is synthetic and cannot authorize real payouts.
 * Uses one Firestore transaction to re-read provenance and create an
 * idempotent private event and candidate tally. NEVER exported in index.js.
 */
const crypto=require("node:crypto");
const {PROJECT,originalClaim}=require(
 "./deda_weekly_original_friend_accepted_action_NOT_EXPORTED.js");
const {validatePrivateFriendClaimInTransaction}=require(
 "./deda_weekly_original_friend_reviewed_signed_claim_NOT_EXPORTED.js");
const {clockState}=require(
 "./deda_weekly_stage31_frozen_league_winner_card_NOT_EXPORTED.js");
const {dayInIraq}=require(
 "./deda_weekly_xp_atomic_shadow_issuer_NOT_EXPORTED.js");

const EVENT_ROOT="deda_weekly_private_friend_signed_xp_events";
const TALLY_ROOT="deda_weekly_private_friend_signed_xp_tallies";
const ISSUER="private_original_friend_signed_candidate_xp_atomic_QA_ONLY";
const ACCOUNT=/^[0-9]{10,16}$/;
const HEX=/^[a-f0-9]{64}$/;
const refuse=why=>{throw Error("DEDA_PRIVATE_FRIEND_CANDIDATE_XP_HOLD_"+why);};
const good=n=>Number.isSafeInteger(n)&&n>=0;
const readDoc=s=>s.exists?s.data():null;
function requirePrivate({db,backendSecret,firstOpenMs,serverNowMs}){
 if(process.env.GCLOUD_PROJECT!==PROJECT||
    process.env.FIRESTORE_EMULATOR_HOST!=="127.0.0.1:8080"||
    process.env.DEDA_FRIEND_REVIEW_EMULATOR_ONLY!=="true"||
    process.env.DEDA_FRIEND_ATOMIC_SHADOW_ONLY!=="true"||
    typeof db?.runTransaction!=="function"||
    !Buffer.isBuffer(backendSecret)||backendSecret.length<32||
    !good(firstOpenMs)||!good(serverNowMs))
   refuse("STRICT_EMULATOR_ONLY");
}
function markerSeal(key,data){
 return crypto.createHmac("sha256",key)
  .update("DEDA_PRIVATE_FRIEND_ATOMIC_XP_MARKER_V1\n")
  .update(JSON.stringify(data)).digest("hex");
}
function expectedMarker({weekId,accountKey,dayId,eventKey,
  approvedAtMs,serverNowMs,score}){
 return Object.freeze({
  schema:1,issuer:ISSUER,emulatorOnly:true,
  canAuthorizeProduction:false,canCreditOriginalXp:false,
  canCreditDiamonds:false,canIssueGift:false,
  originalTaskId:"long_trip",action:"friend_accepted",
  weekId,accountKey,dayId,eventKey,approvedAtMs,
  score,eligiblePrivateWeeklyXp:score,
  source:"SIGNED_PRIVATE_REVIEW_FIXTURE_NOT_USER_CREDIT",
  acceptedAtMs:approvedAtMs,recordedAtMs:serverNowMs,
 });
}
/**
 * A trusted EMULATOR service derives the account/day of the already
 * reviewed friend action (a phone is never allowed to call this function).
 * It revalidates HMAC, original source, synthetic migration and reviewer
 * in the SAME transaction as the candidate event/tally writes.
 *
 * Frozen 00:00-06:00 Baghdad events get a permanent zero-score marker.
 * An action verified after week close never becomes next week's 20 XP.
 */
async function recordPrivateFriendCandidateWeeklyXp({
 db,backendSecret,accountKey,dayId,firstOpenMs,serverNowMs,...extra
}){
 requirePrivate({db,backendSecret,firstOpenMs,serverNowMs});
 if(Object.keys(extra).length||!ACCOUNT.test(accountKey||"")||
    !/^20\d{2}-(0[1-9]|1[0-2])-([0-2]\d|3[01])$/.test(dayId||""))
   refuse("ORIGINAL_ACCOUNT_DAY_ONLY_NO_CLIENT_OVERRIDE");
 const clock=clockState({firstOpenMs,serverNowMs});
 if(!clock.current||!["active","frozen"].includes(clock.phase))
   refuse("NO_ACTIVE_OR_FROZEN_LEAGUE");
 const week=clock.current;
 const {eventKey}=originalClaim(accountKey,dayId);
 const markerRef=db.doc(EVENT_ROOT+"/"+week.weekId+"_"+eventKey);
 const tallyRef=db.doc(TALLY_ROOT+"/"+week.weekId+"_"+accountKey);
 return db.runTransaction(async tx=>{
  const reader={get:async path=>readDoc(await tx.get(db.doc(path)))};
  const proof=await validatePrivateFriendClaimInTransaction({
    reader,backendSecret,accountKey,dayId,eventKey,serverNowMs
  });
  const approvedAtMs=proof.approvedAtMs;
  if(!good(approvedAtMs)||approvedAtMs>serverNowMs||
     serverNowMs-approvedAtMs>300000||
     approvedAtMs<week.openedAtMs||approvedAtMs>=week.nextOpenMs||
     dayInIraq(approvedAtMs)!==dayId)
    refuse("FRIEND_ACTION_NOT_IN_CURRENT_WEEK_OR_DAY");
  const score=clock.phase==="active"&&
    approvedAtMs<week.closeAtMs?20:0;
  const [oldMarkerSnap,oldTallySnap]=await Promise.all([
    tx.get(markerRef),tx.get(tallyRef)
  ]);
  const oldMarker=readDoc(oldMarkerSnap),oldTally=readDoc(oldTallySnap);
  // Retry never increases counters. Tampering with event or total blocks.
  if(oldMarker){
    const expected=expectedMarker({
      weekId:week.weekId,accountKey,dayId,eventKey,approvedAtMs,
      serverNowMs:oldMarker.recordedAtMs,score
    });
    if(!good(oldMarker.recordedAtMs)||
       oldMarker.recordedAtMs<approvedAtMs||
       oldMarker.recordedAtMs>serverNowMs||
       !HEX.test(oldMarker.markerSeal||"")||
       oldMarker.markerSeal!==markerSeal(backendSecret,expected)||
       JSON.stringify({...oldMarker,markerSeal:undefined})!==
         JSON.stringify({...expected,markerSeal:undefined})||
       (score>0&&(!oldTally||
        oldTally.eligiblePrivateWeeklyXp<20||
        oldTally.approvedTaskCount<1)))
       refuse("TAMPERED_OR_PARTIAL_PREVIOUS_CANDIDATE_EVENT");
    return Object.freeze({
      outcome:"already_recorded",privateCandidateWeeklyXpAdded:0,
      actualLevelXpAdded:0,actualLeagueXpAdded:0,
      actualDiamondsAdded:0,canAuthorizeProduction:false,
      emulatorOnly:true
    });
  }
  if(score>0&&oldTally){
    if(oldTally.schema!==1||oldTally.issuer!==ISSUER||
       oldTally.emulatorOnly!==true||
       oldTally.canAuthorizeProduction!==false||
       oldTally.accountKey!==accountKey||
       oldTally.weekId!==week.weekId||
       !good(oldTally.eligiblePrivateWeeklyXp)||
       oldTally.eligiblePrivateWeeklyXp%20!==0||
       !good(oldTally.approvedTaskCount)||
       oldTally.approvedTaskCount*20!==oldTally.eligiblePrivateWeeklyXp||
       oldTally.approvedTaskCount>7)
      refuse("TAMPERED_OR_INVALID_PRIVATE_TALLY");
  }
  const marker=expectedMarker({
    weekId:week.weekId,accountKey,dayId,eventKey,
    approvedAtMs,serverNowMs,score
  });
  tx.create(markerRef,{
    ...marker,markerSeal:markerSeal(backendSecret,marker)
  });
  if(score>0){
    const count=(oldTally?.approvedTaskCount??0)+1;
    const total=(oldTally?.eligiblePrivateWeeklyXp??0)+20;
    if(count>7||total>140)refuse("PRIVATE_WEEKLY_TASK_OVERFLOW");
    const next={
      schema:1,issuer:ISSUER,emulatorOnly:true,
      canAuthorizeProduction:false,canCreditOriginalXp:false,
      canCreditDiamonds:false,canIssueGift:false,
      accountKey,weekId:week.weekId,
      eligiblePrivateWeeklyXp:total,
      approvedTaskCount:count,
      lastOriginalActionAtMs:approvedAtMs,
    };
    if(oldTallySnap.exists)tx.update(tallyRef,next);
    else tx.create(tallyRef,next);
  }
  return Object.freeze({
    outcome:score?"private_candidate_weekly_xp_recorded":"frozen_zero_score",
    privateCandidateWeeklyXpAdded:score,
    actualLevelXpAdded:0,actualLeagueXpAdded:0,
    actualDiamondsAdded:0,canAuthorizeProduction:false,
    emulatorOnly:true
  });
 },{maxAttempts:5});
}
module.exports=Object.freeze({PROJECT,EVENT_ROOT,TALLY_ROOT,ISSUER,
 recordPrivateFriendCandidateWeeklyXp});
