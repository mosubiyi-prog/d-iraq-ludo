"use strict";

/**
 * DEDA weekly contest Stage9 — TRANSACTIONAL SHADOW XP RECEIPT ISSUER.
 *
 * This is a future backend transaction PROTOTYPE, not a real user's XP award.
 * Hard-blocks anything but a dedicated local Firebase emulator project.
 * No export from functions/index.js; never writes DEDA real profile/level XP,
 * task points, wallets, diamond balances, user sessions, or prize ledgers.
 *
 * The existing 100387 client currently credits level XP LOCALLY; the app's
 * existing receipt boolean is not enough to prove that persisted XP.
 * A real backend must first implement privileged proof of successful claim
 * PLUS atomic authoritative user XP write, then adapt this transaction model
 * without using client fields as evidence. The fixture proof below is
 * intentionally named "emulator_fixture_only" so it CANNOT satisfy the
 * production-ready stage6 receipt reader's issuer requirement.
 */
const {
  resolveFutureVerifiedAccount, opaqueReceiptId,
} = require("./deda_weekly_owner_receipt_gate_NOT_EXPORTED.js");
const {verifiedWeek} = require("./deda_weekly_leaderboard_shadow_policy.js");

const PROJECT = "demo-deda-weekly-xp-stage9";
const XP_PER_TASK = 20;
const MAX_PER_DAY = 8;
const TASK = /^[A-Za-z0-9_:-]{1,100}$/;
const ACCOUNT = /^[0-9]{10,16}$/;
const FIXTURE_ISSUER = "emulator_fixture_only_verified_task_v1";
const SHADOW_ISSUER = "emulator_only_weekly_xp_shadow_v1";
const ROOT = Object.freeze({
  proof: "deda_weekly_stage9_shadow_task_proofs",
  receipt: "deda_weekly_stage9_shadow_receipts",
  week: "deda_weekly_stage9_shadow_week_totals",
  day: "deda_weekly_stage9_shadow_day_totals",
});

function abort(reason) {throw Error("DEDA_STAGE9_SHADOW_BLOCK_"+reason);}
function safeInt(n) {return Number.isSafeInteger(n)&&n>=0;}
function dayInIraq(ms) {
  if(!safeInt(ms)) abort("clock");
  const parts=new Intl.DateTimeFormat("en-US",{
    timeZone:"Asia/Baghdad", year:"numeric",month:"2-digit",day:"2-digit",
  }).formatToParts(new Date(ms));
  const data=Object.fromEntries(parts.map(p=>[p.type,p.value]));
  return data.year+"-"+data.month+"-"+data.day;
}
function requireSandbox(db) {
  if(!process.env.FIRESTORE_EMULATOR_HOST ||
      process.env.GCLOUD_PROJECT!==PROJECT ||
      !db || typeof db.runTransaction!=="function" ||
      typeof db.doc!=="function") {
    abort("emulator_only_do_not_pay");
  }
}
function doc(db,path) {
  const ref=db.doc(path);
  if(!ref || typeof ref.path!=="string") abort("invalid_db");
  return ref;
}
function json(snapshot) {
  if(!snapshot?.exists) return null;
  const x=snapshot.data();
  if(!x || typeof x!=="object" || Array.isArray(x)) abort("invalid_doc");
  return x;
}
function checkTotals(value, accountKey, date, type) {
  if(value===null)return {count:0,xp:0};
  if(value.shadowOnly!==true||value.accountKey!==accountKey ||
    (type==="day"?value.dayId!==date:value.weekId!==date) ||
    !safeInt(value.count)||!safeInt(value.xp) ||
    value.xp!==value.count*XP_PER_TASK ||
    !safeInt(value.updatedAtMs)) abort("invalid_shadow_totals");
  return value;
}
/** Never call with raw client-supplied identity, XP amount, UID or time. */
async function simulateAtomicShadowTaskXp({
  db,request,serverNowMs,weekConfig,serverTaskId,
}) {
  requireSandbox(db);
  if(!safeInt(serverNowMs) || !(serverNowMs>0) ||
    !TASK.test(serverTaskId||"")) abort("server_input");
  // User/device must not provide points, phone, wallet or week, including
  // event ID. All are looked up by the future server verified session.
  const identity=await resolveFutureVerifiedAccount({db,request,serverNowMs});
  const accountKey=identity.canonicalAccountKey;
  if(!ACCOUNT.test(accountKey))abort("account");
  const week=verifiedWeek(weekConfig);
  if(serverNowMs<week.startMs || serverNowMs>=week.endMs)
    abort("not_active_week");
  const dayId=dayInIraq(serverNowMs);
  const eventId=opaqueReceiptId({accountKey,dayId,taskId:serverTaskId});
  const proofRef=doc(db,ROOT.proof+"/"+eventId);
  const receiptRef=doc(db,ROOT.receipt+"/"+eventId);
  const dayRef=doc(db,ROOT.day+"/"+eventId.slice(0,0)+
    require("node:crypto").createHash("sha256")
      .update(accountKey+"|"+dayId).digest("hex"));
  const weekRef=doc(db,ROOT.week+"/"+week.weekId+"_"+require("node:crypto")
    .createHash("sha256").update(accountKey).digest("hex"));

  // Transaction is read-then-create/update, unique by canonical account +
  // Baghdad server day + task. Changing phone/UID does not change receipt ID.
  return db.runTransaction(async tx=>{
    if(!tx || typeof tx.get!=="function" || typeof tx.create!=="function" ||
      typeof tx.set!=="function") abort("transaction");
    const [proofSnap,receiptSnap,daySnap,weekSnap]=await Promise.all([
      tx.get(proofRef),tx.get(receiptRef),tx.get(dayRef),tx.get(weekRef),
    ]);
    const prior=json(receiptSnap);
    if(prior!==null) {
      if(prior.issuer!==SHADOW_ISSUER ||prior.shadowOnly!==true||
        prior.accountKey!==accountKey ||prior.taskId!==serverTaskId||
        prior.dayId!==dayId||prior.weekId!==week.weekId||
        prior.amount!==XP_PER_TASK||prior.eventId!==eventId) {
        abort("conflicting_receipt");
      }
      return Object.freeze({
        outcome:"already_recorded",shadowXpAdded:0,receiptId:eventId,
        shadowOnly:true,
      });
    }
    const proof=json(proofSnap);
    if(!proof||proof.issuer!==FIXTURE_ISSUER||
      proof.status!=="emulator_task_and_xp_confirmed"||
      proof.accountKey!==accountKey||proof.dayId!==dayId||
      proof.taskId!==serverTaskId||proof.eventId!==eventId||
      proof.weekId!==week.weekId||proof.taskPointsAwarded!==true||
      proof.levelXpApplied!==true||proof.levelXpAmount!==XP_PER_TASK||
      !safeInt(proof.verifiedAtMs)||
      proof.verifiedAtMs>serverNowMs||
      proof.verifiedAtMs<week.startMs||
      proof.verifiedAtMs>=week.endMs||
      dayInIraq(proof.verifiedAtMs)!==dayId) {
      abort("missing_privileged_task_proof");
    }
    const daily=checkTotals(json(daySnap),accountKey,dayId,"day");
    const weekly=checkTotals(json(weekSnap),accountKey,week.weekId,"week");
    if(daily.count>=MAX_PER_DAY||daily.xp+XP_PER_TASK>MAX_PER_DAY*XP_PER_TASK)
      abort("daily_claim_limit");
    if(!safeInt(weekly.xp+XP_PER_TASK)||!safeInt(weekly.count+1))
      abort("xp_overflow");
    // Writes are ONLY dedicated emulator-only shadow documents; a real
    // account's level XP is never changed by this function.
    tx.create(receiptRef,{
      issuer:SHADOW_ISSUER,shadowOnly:true,accountKey,taskId:serverTaskId,
      dayId,weekId:week.weekId,eventId,amount:XP_PER_TASK,
      verifiedAtMs:proof.verifiedAtMs,createdAtMs:serverNowMs,
    });
    tx.set(dayRef,{
      shadowOnly:true,accountKey,dayId,count:daily.count+1,
      xp:daily.xp+XP_PER_TASK,updatedAtMs:serverNowMs,
    });
    tx.set(weekRef,{
      shadowOnly:true,accountKey,weekId:week.weekId,count:weekly.count+1,
      xp:weekly.xp+XP_PER_TASK,updatedAtMs:serverNowMs,
    });
    return Object.freeze({
      outcome:"shadow_recorded",shadowXpAdded:XP_PER_TASK,receiptId:eventId,
      shadowOnly:true,
    });
  });
}
module.exports=Object.freeze({
  PROJECT,ROOT,XP_PER_TASK,simulateAtomicShadowTaskXp,dayInIraq,
});
