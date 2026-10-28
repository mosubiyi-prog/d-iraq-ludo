"use strict";

/**
 * DEDA Stage30 — trusted-server-action TO task-XP-proof BRIDGE, REAL EMULATOR
 * ONLY. This deliberately contains NO real task-verification producer. The
 * source documents are emulator fixtures seeded by trusted Admin SDK tests.
 * NOT a Cloud Function; NEVER exported from functions/index.js or used for
 * live DEDA. In particular, a UI tap / local JSON / premium ID is NOT proof.
 *
 * Flow: private committed server action -> protected task proof (once) ->
 * Stage9 atomically issues +20 isolated SHADOW XP -> Stage29 same ranks to
 * player/admin preview. Original level XP, +5 ordinary task points, real
 * wallets, published functions and user records are never written.
 */
const {PROJECT,ROOT,dayInIraq}=require(
  "./deda_weekly_xp_atomic_shadow_issuer_NOT_EXPORTED.js");
const {opaqueReceiptId,resolveFutureVerifiedAccount}=require(
  "./deda_weekly_owner_receipt_gate_NOT_EXPORTED.js");
const {verifiedWeek}=require("./deda_weekly_leaderboard_shadow_policy.js");

const ACTION_ROOT="deda_weekly_stage30_server_action_fixtures";
const SOURCE_ISSUER="emulator_server_written_task_action_fixture_only_v1";
const TASK_PROOF_ISSUER="emulator_fixture_only_verified_task_v1";
const SOURCES=Object.freeze({
  share_personal_location:"server_location_share_committed",
  share_registered_place:"server_owner_place_share_committed",
});
const EVENT=/^[a-f0-9]{64}$/;
function block(code){throw Error("DEDA_STAGE30_PROOF_BLOCK_"+code);}
function validInt(n){return Number.isSafeInteger(n)&&n>=0;}
function requireEmulator(db){
  if(!process.env.FIRESTORE_EMULATOR_HOST ||
     process.env.GCLOUD_PROJECT!==PROJECT ||
     !db||typeof db.doc!=="function"||
     typeof db.runTransaction!=="function")block("emulator_only");
}
function record(snap){
  if(!snap?.exists||typeof snap.data!=="function")return null;
  const value=snap.data();
  if(!value||typeof value!=="object"||Array.isArray(value))
    block("invalid_server_document");
  return value;
}
function checkAction(action,{account,week,taskId,dayId,eventId,now}){
  if(!action||action.issuer!==SOURCE_ISSUER||
     action.source!==SOURCES[taskId]||
     action.status!=="committed"||action.emulatorOnly!==true||
     action.accountKey!==account||action.taskId!==taskId||
     action.dayId!==dayId||action.weekId!==week.weekId||
     action.eventId!==eventId||action.taskPointsAwarded!==true||
     action.levelXpApplied!==true||action.levelXpAmount!==20||
     !validInt(action.verifiedAtMs)||
     action.verifiedAtMs>now||
     action.verifiedAtMs<week.startMs||
     action.verifiedAtMs>=week.endMs||
     dayInIraq(action.verifiedAtMs)!==dayId){
    block("no_privileged_committed_action_evidence");
  }
}
/**
 * Only the server may select taskId, week config and clock. Caller must hold
 * verified Firebase Auth/App Check. Fake fixture source is not production
 * evidence. Read-and-create share one Firestore transaction for deduplication.
 *
 * Server action and task XP award need a COMMON real trusted transaction in
 * future production — do not treat this staged emulator model as such.
 */
async function simulateStage30ProofFromServerAction({
  db,request,serverNowMs,weekConfig,serverTaskId,
}){
  requireEmulator(db);
  if(!validInt(serverNowMs)||serverNowMs<=0)
    block("server_clock");
  if(!Object.prototype.hasOwnProperty.call(SOURCES,serverTaskId))
    block("no_trusted_action_issuer_for_task");
  const week=verifiedWeek(weekConfig);
  if(serverNowMs<week.startMs||serverNowMs>=week.endMs)
    block("no_active_week");
  const identity=await resolveFutureVerifiedAccount({
    db,request,serverNowMs,
  });
  const dayId=dayInIraq(serverNowMs);
  const account=identity.canonicalAccountKey;
  const eventId=opaqueReceiptId({
    accountKey:account,dayId,taskId:serverTaskId,
  });
  if(!EVENT.test(eventId))block("event_hash");
  const sourceRef=db.doc(ACTION_ROOT+"/"+eventId);
  const proofRef=db.doc(ROOT.proof+"/"+eventId);
  if(sourceRef.path===proofRef.path)block("namespace_collision");
  return db.runTransaction(async tx=>{
    const [sourceSnap,priorSnap]=await Promise.all([
      tx.get(sourceRef),tx.get(proofRef),
    ]);
    const action=record(sourceSnap);
    // Always revalidate the ORIGINAL committed server action even on replay.
    checkAction(action,{
      account,week,taskId:serverTaskId,dayId,eventId,now:serverNowMs,
    });
    const prior=record(priorSnap);
    if(prior){
      if(prior.issuer!==TASK_PROOF_ISSUER||
        prior.status!=="emulator_task_and_xp_confirmed"||
        prior.accountKey!==account||prior.taskId!==serverTaskId||
        prior.dayId!==dayId||prior.weekId!==week.weekId||
        prior.eventId!==eventId||
        prior.verifiedAtMs!==action.verifiedAtMs||
        prior.taskPointsAwarded!==true||
        prior.levelXpApplied!==true||prior.levelXpAmount!==20){
        block("conflicting_existing_proof");
      }
      return Object.freeze({
        outcome:"already_proven",eventId,proofCreated:false,
        emulatorOnly:true,
      });
    }
    tx.create(proofRef,{
      issuer:TASK_PROOF_ISSUER,status:"emulator_task_and_xp_confirmed",
      accountKey:account,taskId:serverTaskId,dayId,
      weekId:week.weekId,eventId,
      verifiedAtMs:action.verifiedAtMs,taskPointsAwarded:true,
      levelXpApplied:true,levelXpAmount:20,
    });
    return Object.freeze({
      outcome:"proof_recorded",eventId,proofCreated:true,
      emulatorOnly:true,
    });
  });
}
module.exports=Object.freeze({
  PROJECT,ACTION_ROOT,SOURCE_ISSUER,SOURCES,
  simulateStage30ProofFromServerAction,
});
