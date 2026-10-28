"use strict";
/**
 * STAGE34 — FUTURE-STATE ATOMIC CANONICAL XP TRANSACTION, EMULATOR ONLY.
 *
 * This is NOT the original app's XP ledger and NOT an exported Cloud Function.
 * Protected source, identity, claim and account migration are seeded by ADMIN
 * SDK FIXTURES in local Firestore. These strings can never authenticate live
 * tasks, historic local XP or a new phone. The module intentionally fails if
 * the original XP migration has not been independently reconciled.
 *
 * It demonstrates one atomic transaction: trusted completed claim + immutable
 * +20 lifetime LEVEL XP + duplicate-proof receipt + weekly score (if eligible).
 * A task completed during the frozen midnight interval still earns level XP,
 * while competition XP stays zero. No DEDA real data is written.
 */
const crypto=require("node:crypto");
const {PROJECT,dayInIraq}=require(
  "./deda_weekly_xp_atomic_shadow_issuer_NOT_EXPORTED.js");
const {resolveFutureVerifiedAccount,opaqueReceiptId}=require(
  "./deda_weekly_owner_receipt_gate_NOT_EXPORTED.js");
const {clockState,windowFor}=require(
  "./deda_weekly_stage31_frozen_league_winner_card_NOT_EXPORTED.js");
const SHADOW=Object.freeze({
  account:"deda_weekly_stage34_shadow_level_accounts",
  task:"deda_weekly_stage34_shadow_trusted_claim_fixtures",
  receipt:"deda_weekly_stage34_shadow_level_xp_receipts",
  league:"deda_weekly_stage34_shadow_league_receipts",
});
const ISSUER="stage34_emulator_only_independently_verified_claim_fixture";
const MIGRATION="stage34_emulator_only_server_reconciled_baseline_fixture";
const TASK="share_personal_location", XP=20, TASK_POINTS=5;
function block(s){throw Error("DEDA_STAGE34_PRIVATE_BLOCK_"+s);}
function unsigned(v){return Number.isSafeInteger(v)&&v>=0;}
function requireEmulator(db){
  if(process.env.GCLOUD_PROJECT!==PROJECT ||
    !process.env.FIRESTORE_EMULATOR_HOST ||
    !db||typeof db.runTransaction!=="function"||typeof db.doc!=="function")
    block("local_emulator_only");
}
function get(snap,name){
  if(!snap?.exists)block("missing_"+name);
  const v=snap.data();
  if(!v||typeof v!=="object"||Array.isArray(v))block("invalid_"+name);
  return v;
}
function hash(account){
  return crypto.createHash("sha256").update(account).digest("hex");
}
function strictReconciled(x,account){
  if(x.issuer!==MIGRATION||x.emulatorOnly!==true||
     x.canonicalAccountKey!==account||x.status!=="reconciled"||
     x.legacyLocalDataRetained!==true||
     x.authoritativeBaselineVerified!==true||
     x.baselineTaskClaimsReviewed!==true||
     !unsigned(x.originalLevelXpBaseline)||
     !unsigned(x.levelXp)||!unsigned(x.newAwardsCount)||
     x.levelXp!==x.originalLevelXpBaseline+XP*x.newAwardsCount||
     !unsigned(x.revision)||x.revision<1)block("unverified_or_conflicting_baseline");
}
function strictClaim(x,account,receiptId,dayId,now){
  if(x.issuer!==ISSUER||x.emulatorOnly!==true||
     x.canonicalAccountKey!==account||x.taskId!==TASK||
     x.taskReceiptId!==receiptId||x.dayId!==dayId||
     x.claimType!=="daily_task_claim"||
     x.sourceType!=="original_app_location_share"||
     x.backendCheckedOriginalShare!==true||
     x.backendCheckedActualTaskClaim!==true||
     x.ordinaryTaskPointsConfirmed!==true||
     x.originalOrdinaryTaskPoints===TASK_POINTS||
     x.levelXpAlreadyApplied!==false||
     !unsigned(x.verifiedAtMs)||x.verifiedAtMs>now||
     now-x.verifiedAtMs>5*60*1000||
     dayInIraq(x.verifiedAtMs)!==dayId)
    block("untrusted_or_stale_task_claim_fixture");
}
/** Valid for *private simulated completed daily claims only*.
 * Caller supplies no amount, week, task, accountKey, UID, candidate, alias,
 * gift, score or event ID. These are SERVER derived from identity and time.
 */
async function simulateLevelXpAndLeagueReceipt({db,request,firstOpenMs,serverNowMs}){
  requireEmulator(db);
  if(!unsigned(serverNowMs))block("invalid_clock");
  const owner=await resolveFutureVerifiedAccount({db,request,serverNowMs});
  const account=owner.canonicalAccountKey;
  const dayId=dayInIraq(serverNowMs);
  const receiptId=opaqueReceiptId({accountKey:account,dayId,taskId:TASK});
  const ac=db.doc(SHADOW.account+"/"+hash(account));
  const task=db.doc(SHADOW.task+"/"+receiptId);
  const receipt=db.doc(SHADOW.receipt+"/"+receiptId);
  const clock=clockState({firstOpenMs,serverNowMs});
  const eligible=clock.leagueScoringAllowed;
  const leagueWeek=clock.current;
  const leagueDoc=eligible && leagueWeek ?
    db.doc(SHADOW.league+"/"+leagueWeek.weekId+"_"+receiptId):null;

  return db.runTransaction(async tx=>{
    const [acSnap,taskSnap,existingSnap,leagueSnap]=await Promise.all([
      tx.get(ac),tx.get(task),tx.get(receipt),
      leagueDoc?tx.get(leagueDoc):Promise.resolve(null)
    ]);
    const baseline=get(acSnap,"reconciled_level_account");
    strictReconciled(baseline,account);
    if(existingSnap.exists){
      const old=get(existingSnap,"existing_level_receipt");
      if(old.emulatorOnly!==true||old.accountKey!==account||
         old.taskId!==TASK||old.dayId!==dayId||
         old.amount!==XP||old.receiptId!==receiptId||
         !["league","frozen"].includes(old.competitionStatus)||
         (old.competitionStatus==="league"?
            old.weekId==null:old.weekId!==null))
        block("conflicting_existing_receipt");
      return Object.freeze({outcome:"already_awarded",
        levelXpAdded:0,leagueXpAdded:0,shadowOnly:true});
    }
    const claim=get(taskSnap,"independent_trusted_task_claim");
    strictClaim(claim,account,receiptId,dayId,serverNowMs);
    if(leagueSnap?.exists)block("orphan_league_receipt");
    const next=baseline.levelXp+XP;
    if(!unsigned(next)||!unsigned(baseline.newAwardsCount+1)||
       !unsigned(baseline.revision+1))block("xp_overflow");
    const weekId=eligible?leagueWeek.weekId:null;
    tx.create(receipt,{
      emulatorOnly:true,issuer:"stage34_atomic_level_fixture_v1",
      accountKey:account,taskId:TASK,dayId,receiptId,amount:XP,
      verifiedAtMs:claim.verifiedAtMs,createdAtMs:serverNowMs,
      weekId,competitionStatus:eligible?"league":"frozen",
    });
    tx.update(ac,{
      levelXp:next,newAwardsCount:baseline.newAwardsCount+1,
      revision:baseline.revision+1,updatedAtMs:serverNowMs,
    });
    if(leagueDoc){
      tx.create(leagueDoc,{
        issuer:"stage34_atomic_weekly_fixture_v1",
        emulatorOnly:true,weekId:leagueWeek.weekId,accountKey:account,
        taskId:TASK,dayId,receiptId,amount:XP,
        verifiedAtMs:claim.verifiedAtMs
      });
    }
    return Object.freeze({outcome:"shadow_level_recorded",
      levelXpAdded:XP,leagueXpAdded:eligible?XP:0,shadowOnly:true});
  });
}
module.exports=Object.freeze({
  PROJECT,XP,SHADOW,ISSUER,MIGRATION,TASK,TASK_POINTS,
  simulateLevelXpAndLeagueReceipt,hash,
});
