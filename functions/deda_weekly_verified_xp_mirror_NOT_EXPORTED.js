"use strict";
/**
 * Internal-only bridge: previously applied DEDA level XP -> weekly leaderboard.
 * Not a callable. No client-reported XP/score, no writes to user progress,
 * rewards, account bindings, wallets, premium IDs, or original 100396 app.
 *
 * A separate, approved server action producer must create independently
 * signed proofs. Existing LOCAL task claims are NOT such proof.
 */
const {createHash, createHmac, timingSafeEqual} = require("node:crypto");
const progress = require("../tools/app_stability/progress_archive/reconcile-core.cjs");
const {TASK_IDS} = require("./deda_weekly_original_eight_task_source_gate_NOT_EXPORTED.js");
const {windowFor} = require("./deda_weekly_stage31_frozen_league_winner_card_NOT_EXPORTED.js");
const ACCOUNT=/^[0-9]{10,16}$/;
const HEX=/^[a-f0-9]{64}$/;
const DAY=/^20\d{2}-(?:0[1-9]|1[0-2])-(?:0[1-9]|[12]\d|3[01])$/;
const TASK=/^daily-task\|(20\d{2}-\d{2}-\d{2})\|([a-z_]+)$/;
const DOMAIN="DEDA_WEEKLY_TRUSTED_ACTION_V1\n";
class TaskXpHold extends Error{
 constructor(reason){super("DEDA_WEEKLY_XP_HOLD_"+reason);this.name="TaskXpHold";}
}
const hold=x=>{throw new TaskXpHold(x);};
function seal(key,info){
 if(!Buffer.isBuffer(key)||key.length<32)throw Error("SERVER_HMAC_SECRET_REQUIRED");
 return createHmac("sha256",key).update(DOMAIN).update(JSON.stringify([
  info.accountKey,info.taskId,info.dayId,info.eventKey,
  info.appliedVersion,info.awardedAtMs,info.actionId,
 ])).digest("hex");
}
function dayInBaghdad(timestamp){
 const f=new Intl.DateTimeFormat("en-CA",{
  timeZone:"Asia/Baghdad",year:"numeric",month:"2-digit",day:"2-digit",
 });
 const x=Object.fromEntries(f.formatToParts(new Date(timestamp)).map(p=>[p.type,p.value]));
 return x.year+"-"+x.month+"-"+x.day;
}
function asMs(t){
 const n=t?.toMillis?.();
 if(!Number.isSafeInteger(n)||n<=0)hold("INVALID_SERVER_TIMESTAMP");
 return n;
}
function verifiedDetails({event,eventKey,proof,accountKey,secret,nowMs}){
 if(!event||event.format!==1||event.accountKey!==accountKey||
    event.eventKey!==eventKey||event.appliedVersion<2||
    !Number.isSafeInteger(event.appliedVersion))hold("NOT_APPLIED");
 const receipt=progress.parseReceipt(event.receipt,accountKey);
 if(eventKey!==progress.eventKey(receipt)||
    receipt.source!=="task-claim-v1"||receipt.kind!=="award"||
    receipt.delta.xp!==20||receipt.delta.points!==5||
    receipt.delta.coins!==10||receipt.delta.earnedDiamonds!==0)
  hold("INVALID_TASK_LEVEL_XP");
 const match=TASK.exec(receipt.sourceId);
 if(!match||!DAY.test(match[1])||!TASK_IDS.includes(match[2]))
  hold("UNKNOWN_TASK");
 const awardedAtMs=asMs(event.createdAt);
 if(dayInBaghdad(awardedAtMs)!==match[1]||awardedAtMs>nowMs||
    awardedAtMs<0)hold("WRONG_SERVER_DAY");
 if(!event.afterBalances||!Number.isSafeInteger(event.afterBalances.xp)||
    event.afterBalances.xp<20)hold("NOT_REAL_APPLIED_XP");
 const signed={
  accountKey,dayId:match[1],taskId:match[2],eventKey,
  appliedVersion:event.appliedVersion,awardedAtMs,
  actionId:proof?.actionId,
 };
 // A client receipt, checkbox, self-attested Google ID or locally cached XP
 // never provides independent original-action proof.
 if(!proof||proof.schema!==1||
    proof.issuer!=="deda_server_verified_original_action_v1"||
    proof.productionApproved!==true||
    typeof signed.actionId!=="string"||
    !/^[A-Za-z0-9_-]{12,96}$/.test(signed.actionId)||
    !HEX.test(proof.signature||"")||
    !["accountKey","dayId","taskId","eventKey","appliedVersion","awardedAtMs"]
      .every(k=>proof[k]===signed[k]))hold("UNVERIFIED_ACTION");
 const expected=seal(secret,signed);
 if(!timingSafeEqual(Buffer.from(proof.signature,"hex"),
    Buffer.from(expected,"hex")))hold("BAD_ACTION_SIGNATURE");
 return signed;
}
/**
 * Atomic, account-keyed weekly mirror. Source already credited +20 XP.
 * Exactly one event for each account / Baghdad day / task, even across phones.
 *
 * A valid event during 00:00-06:00 freeze is NOT credited to either week;
 * this does not reverse the lifetime level XP on the original account.
 */
async function mirrorVerifiedTaskXp({
 db,accountKey,eventKey,secret,firstOpenMs,nowMs=Date.now(),
}){
 if(!db||typeof db.runTransaction!=="function"||
    !ACCOUNT.test(accountKey||"")||!HEX.test(eventKey||"")||
    !Number.isSafeInteger(nowMs)||nowMs<=0)hold("BAD_INPUT");
 if(!Buffer.isBuffer(secret)||secret.length<32)
  throw Error("SERVER_HMAC_SECRET_REQUIRED");
 const index=Math.floor((nowMs-firstOpenMs)/(7*86400000));
 if(index<0||!Number.isSafeInteger(index))hold("WEEK_NOT_OPEN");
 const current=windowFor(firstOpenMs,index);
 const doc=(path)=>db.doc(path);
 const digest=createHash("sha256").update(accountKey).digest("hex");
 const weekRoot="deda_weekly_verified_xp_mirror_private/"+current.weekId;
 const scoreRef=doc(weekRoot+"/scores/"+digest);
 const receiptRef=doc(weekRoot+"/receipts/"+eventKey);
 const sourceRef=doc("deda_verified_progress/"+accountKey+"/events/"+eventKey);
 const proofRef=doc("deda_weekly_server_action_proofs/"+eventKey);
 const directoryRef=doc("deda_account_directory/"+accountKey);
 try{
  return await db.runTransaction(async tx=>{
   const [directoryS,sourceS,proofS,priorS,scoreS]=await Promise.all([
    tx.get(directoryRef),tx.get(sourceRef),tx.get(proofRef),
    tx.get(receiptRef),tx.get(scoreRef),
   ]);
   const d=directoryS.exists?directoryS.data():null;
   if(d?.accountKey!==accountKey||d.active!==true)
     hold("UNKNOWN_CANONICAL_ACCOUNT");
   const event=sourceS.exists?sourceS.data():null;
   const proof=proofS.exists?proofS.data():null;
   const detail=verifiedDetails({event,eventKey,proof,accountKey,secret,nowMs});
   // The event's canonical server timestamp, not device clock or sync time,
   // decides which league week it belongs to.
   if(detail.awardedAtMs<current.openedAtMs||
      detail.awardedAtMs>=current.nextOpenMs)
     hold("WRONG_COMPETITION_WEEK");
   if(detail.awardedAtMs>=current.closeAtMs ||
      nowMs>=current.closeAtMs)
     return Object.freeze({status:"WEEK_FROZEN",counted:false,pointsAdded:0});
   if(priorS.exists){
    const prior=priorS.data();
    if(prior.accountDigest!==digest||prior.eventKey!==eventKey||
       prior.dayId!==detail.dayId||prior.taskId!==detail.taskId)
      hold("REPLAY_CONFLICT");
    return Object.freeze({status:"ALREADY_COUNTED",counted:false,
      pointsAdded:0,weeklyPoints:scoreS.exists?scoreS.data().weeklyPoints:0});
   }
   const original=scoreS.exists?scoreS.data():null;
   if(original&&(
      original.accountDigest!==digest||
      original.accountKey!==accountKey||
      original.weekId!==current.weekId||
      !Number.isSafeInteger(original.weeklyPoints)||
      !Number.isSafeInteger(original.verifiedTaskCompletions)))
    hold("CORRUPT_WEEK_SCORE");
   const currentPoints=original?.weeklyPoints??0;
   const taskCount=original?.verifiedTaskCompletions??0;
   const dayTaskKey=detail.dayId+"|"+detail.taskId;
   // Same source/day/task cannot credit twice even if new event IDs appear.
   // The day-task lock is created atomically with tally + receipt.
   const dayLockRef=doc(weekRoot+"/dayTaskLocks/"+
     createHash("sha256").update(digest+"|"+dayTaskKey).digest("hex"));
   const lockS=await tx.get(dayLockRef);
   if(lockS.exists)hold("DUPLICATE_DAY_TASK");
   tx.create(dayLockRef,{accountDigest:digest,dayTaskKey,eventKey});
   tx.create(receiptRef,{accountDigest:digest,eventKey,dayId:detail.dayId,
     taskId:detail.taskId,weeklyPoints:20,source:"already-applied-level-xp"});
   const next={
    // PRIVATE Admin SDK only: canonical key is needed to resolve names and
    // public IDs securely when serving the global leaderboard. Never return
    // this field or expose this collection through client Firestore Rules.
    accountDigest:digest,accountKey,weekId:current.weekId,
    weeklyPoints:currentPoints+20,
    verifiedTaskCompletions:taskCount+1,
    lastEarnedAtMs:Math.max(original?.lastEarnedAtMs??0,detail.awardedAtMs),
    rewardsCredited:false,levelXpChanged:false,
   };
   if(!Number.isSafeInteger(next.weeklyPoints)||
      !Number.isSafeInteger(next.verifiedTaskCompletions))
    hold("WEEK_OVERFLOW");
   tx.set(scoreRef,next);
   return Object.freeze({status:"COUNTED",counted:true,
     pointsAdded:20,weeklyPoints:next.weeklyPoints,
     weekId:current.weekId});
  },{maxAttempts:5});
 }catch(e){
  if(e instanceof TaskXpHold)throw e;
  throw Error("DEDA_WEEKLY_XP_BACKEND_UNAVAILABLE");
 }
}
module.exports={mirrorVerifiedTaskXp,verifiedDetails,seal,TaskXpHold};
