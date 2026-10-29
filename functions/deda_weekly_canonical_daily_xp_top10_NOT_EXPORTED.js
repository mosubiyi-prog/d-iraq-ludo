"use strict";
/**
 * First concrete canonical-ACCOUNT weekly scoreboard over DEDA's EXISTING
 * verified-progress applied task receipts. Read-only. No local phone points,
 * phone UID, task-checkbox flag, wallet or manager bonus can enter the score.
 *
 * This prototype requires a distinct server-signed original ACTION proof for
 * every applied receipt. Today only a share-action path has a QA producer;
 * all other original tasks will remain absent until proper issuers exist.
 * The strict DEMO PROJECT guard means this must NEVER be exported or used as
 * a source of real prizes. The same account survives UID/phone replacement.
 */
const {createHash,createHmac,timingSafeEqual}=require("node:crypto");
const core=require("../tools/app_stability/progress_archive/reconcile-core.cjs");
const {TASK_IDS}=require("./deda_weekly_original_eight_task_source_gate_NOT_EXPORTED.js");
const {windowFor,PRIZES}=require("./deda_weekly_stage31_frozen_league_winner_card_NOT_EXPORTED.js");
const PROJECT="demo-deda-restore-readiness";
const ROSTER="deda_weekly_private_canonical_account_roster/config";
const PROOFS="deda_weekly_private_canonical_task_source_proofs";
const ACCOUNT=/^[0-9]{10,16}$/, DAY=/^20\d{2}-(0[1-9]|1[0-2])-([0-2]\d|3[01])$/;
const RECEIPT=/^daily-task\|(20\d{2}-[0-9]{2}-[0-9]{2})\|([a-z_]+)$/;
const PUBLIC=/^@DEDA-[A-Z0-9]{4,12}$/,ORIGINAL=/^@DEDA-[A-Z0-9]{6}$/;
const HEX=/^[a-f0-9]{64}$/;
function fail(reason){throw Error("DEDA_CANONICAL_WEEKLY_SOURCE_HOLD_"+reason);}
function safeInteger(n){return Number.isSafeInteger(n)&&n>=0;}
function safeName(n){return typeof n==="string"&&n.length>=2&&n.length<=60&&
  !/[\x00-\x1f\x7f@]/.test(n)&&!/\b0[0-9]{10}\b/.test(n)&&
  !/\S+@\S+/.test(n);}
function ms(value){const v=value?.toMillis?.();if(!safeInteger(v))fail("TIMESTAMP");return v;}
function dayBaghdad(t){
  const pieces=new Intl.DateTimeFormat("en-CA",{
    timeZone:"Asia/Baghdad",year:"numeric",month:"2-digit",day:"2-digit",
  }).formatToParts(new Date(t));
  const p=Object.fromEntries(pieces.map(x=>[x.type,x.value]));
  return p.year+"-"+p.month+"-"+p.day;
}
function canonicalProofBody({accountKey,dayId,taskId,eventKey,appliedVersion,awardedAtMs}){
  return {
    schema:1,issuer:"private_verified_original_task_source_QA_ONLY",
    emulatorOnly:true,productionReady:false,canCreditDiamonds:false,
    accountKey,dayId,taskId,eventKey,appliedVersion,awardedAtMs,
  };
}
function seal(key,body){
  return createHmac("sha256",key).update("DEDA_CANONICAL_TASK_V1\n")
    .update(JSON.stringify(body)).digest("hex");
}
function enforceEnvironment(db,secret,nowMs,firstOpenMs,weekIndex){
  if(process.env.GCLOUD_PROJECT!==PROJECT||
     process.env.FIRESTORE_EMULATOR_HOST!=="127.0.0.1:8080"||
     process.env.DEDA_CANONICAL_LEAGUE_EMULATOR_ONLY!=="true"||
     !db||typeof db.doc!=="function"||typeof db.collection!=="function"||
     !Buffer.isBuffer(secret)||secret.length<32||
     !safeInteger(nowMs)||!safeInteger(firstOpenMs)||
     !Number.isSafeInteger(weekIndex)||weekIndex<0)
   fail("EMULATOR_ONLY");
}
async function read(db,path){
 const s=await db.doc(path).get();return s.exists?s.data():null;
}
function validateEvent(e,account,week,nowMs){
 if(!e||e.format!==1||e.accountKey!==account||
    !HEX.test(e.eventKey||"")||!safeInteger(e.appliedVersion)||
    e.appliedVersion<2||!e.receipt||!e.afterBalances)
   fail("NOT_APPLIED_CANONICAL_EVENT");
 const r=core.parseReceipt(e.receipt,account);
 if(e.eventKey!==core.eventKey(r)||r.source!=="task-claim-v1"||
    r.kind!=="award"||r.delta.points!==5||
    r.delta.coins!==10||r.delta.xp!==20||
    r.delta.earnedDiamonds!==0)
   fail("NOT_ORIGINAL_TASK_XP");
 const parsed=RECEIPT.exec(r.sourceId||"");
 if(!parsed||!DAY.test(parsed[1])||!TASK_IDS.includes(parsed[2]))
   fail("UNKNOWN_OR_FABRICATED_TASK");
 const awardedAtMs=ms(e.createdAt);
 if(awardedAtMs>nowMs||dayBaghdad(awardedAtMs)!==parsed[1])
   fail("SERVER_DAY_MISMATCH");
 if(awardedAtMs<week.openedAtMs||awardedAtMs>=week.nextOpenMs)
   fail("RECEIPT_OUTSIDE_WEEK");
 if(!safeInteger(e.afterBalances.xp)||e.afterBalances.xp<20||
    !safeInteger(e.afterBalances.points)||
    !safeInteger(e.afterBalances.coins)||
    !safeInteger(e.afterBalances.earnedDiamonds))
   fail("INVALID_APPLIED_PROGRESS");
 return {taskId:parsed[2],dayId:parsed[1],awardedAtMs,eventKey:e.eventKey,
   appliedVersion:e.appliedVersion};
}
async function validateAccountIdentity(db,key){
 const d=await read(db,"deda_account_directory/"+key);
 const p=await read(db,"deda_account_profiles/"+key);
 const ids=await read(db,"deda_owned_identifier_accounts/"+
   createHash("sha256").update(key).digest("hex"));
 if(d?.accountKey!==key||d.active!==true||
    p?.accountKey!==key||!safeName(p.name))
   fail("UNKNOWN_ACCOUNT_OR_PUBLIC_NAME");
 const oldUid=d.createdUid;
 if(typeof oldUid!=="string"||!oldUid.length)fail("MISSING_ORIGINAL_OWNER");
 const originalUser=await read(db,"users/"+oldUid);
 const originalId=originalUser?.sharePersonalId;
 if(originalUser?.accountKey!==key||!ORIGINAL.test(originalId||""))
   fail("UNKNOWN_ORIGINAL_PUBLIC_ID");
 const route=await read(db,"deda_share_ids/"+originalId);
 if(route?.kind!=="personal"||route?.publicId!==originalId||
    route?.active!==true||typeof route.ownerUid!=="string")
   fail("UNVERIFIED_PUBLIC_ID_ROUTE");
 const currentUid=route.ownerUid;
 const current=await read(db,"users/"+currentUid);
 const accountAuthority=await read(db,"deda_migration_account_authority/"+key);
 const personalAuthority=await read(db,"deda_migration_spend_authority/"+originalId);
 if(current?.accountKey!==key||
    (currentUid!==oldUid&&(
      accountAuthority?.activeUid!==currentUid||
      personalAuthority?.activeUid!==currentUid||
      accountAuthority?.originalUid!==oldUid||
      personalAuthority?.originalUid!==oldUid||
      (accountAuthority?.status!=="new-device-exclusive")||
      (personalAuthority?.status!=="new-device-exclusive"))))
   fail("UNAUTHORIZED_PHONE_HANDOVER");
 const activeId=ids?.activeId||originalId;
 if(!PUBLIC.test(activeId)||ids&&(
      ids.accountKey!==key||ids.originalId!==originalId||
      !Array.isArray(ids.ownedIds)||!ids.ownedIds.includes(activeId)))
   fail("UNVERIFIED_ACTIVE_IDENTIFIER");
 return {displayName:p.name,activePublicId:activeId};
}
async function projectCanonicalEarnedXpTopTen({
 db,backendSecret,firstOpenMs,weekIndex,serverNowMs,...extras
}){
 enforceEnvironment(db,backendSecret,serverNowMs,firstOpenMs,weekIndex);
 if(Object.keys(extras).length)fail("CLIENT_SCORE_OR_PHONE_OVERRIDE");
 const week=windowFor(firstOpenMs,weekIndex);
 if(serverNowMs<week.openedAtMs)fail("WEEK_NOT_STARTED");
 const roster=await read(db,ROSTER);
 const keys=roster?.accountKeys;
 if(roster?.emulatorOnly!==true||roster?.productionReady!==false||
    !Array.isArray(keys)||keys.length>100||
    new Set(keys).size!==keys.length||
    keys.some(k=>!ACCOUNT.test(k||"")))
   fail("PRIVATE_ROSTER_MISSING_OR_INVALID");
 const ranks=[];
 for(const key of keys){
  const state=await read(db,"deda_verified_progress/"+key);
  if(!state)continue; // no verified cloud progress = no fake score
  core.parseState(state,key);
  const events=await db.collection("deda_verified_progress").doc(key)
    .collection("events").get();
  if(events.size>350)fail("UNBOUNDED_PROOF_EVENTS");
  const seen=new Set(),days=new Set();
  let points=0,lastAtMs=0,count=0;
  for(const snap of events.docs){
   const e=snap.data();
   // Ignore non-task receipts and original baseline, never use current XP
   // balance as an eligible competitive delta.
   if(e?.receipt?.source!=="task-claim-v1")continue;
   const event=validateEvent(e,key,week,serverNowMs);
   if(snap.id!==event.eventKey||seen.has(event.eventKey))
     fail("DUPLICATE_CANONICAL_RECEIPT");
   seen.add(event.eventKey);
   const dayTask=event.dayId+"|"+event.taskId;
   if(days.has(dayTask))fail("DUPLICATE_DAY_TASK");
   days.add(dayTask);
   const proofBody=canonicalProofBody({
    accountKey:key,dayId:event.dayId,taskId:event.taskId,
    eventKey:event.eventKey,appliedVersion:event.appliedVersion,
    awardedAtMs:event.awardedAtMs,
   });
   const proof=await read(db,PROOFS+"/"+event.eventKey);
   const digest=proof?.seal;
   if(!HEX.test(digest||"")||
      !timingSafeEqual(Buffer.from(digest,"hex"),
        Buffer.from(seal(backendSecret,proofBody),"hex"))||
      Object.keys(proof).length!==Object.keys(proofBody).length+1||
      Object.keys(proofBody).some(k=>proof[k]!==proofBody[k]))
    fail("MISSING_INDEPENDENT_SIGNED_ACTION_PROOF");
   // Task XP remains lifetime XP regardless of competition freeze; the
   // only league-eligible slice is from trusted server timestamp BEFORE 00.
   if(event.awardedAtMs>=week.closeAtMs)continue;
   points+=20;count++;lastAtMs=Math.max(lastAtMs,event.awardedAtMs);
  }
  if(!points)continue;
  const identity=await validateAccountIdentity(db,key);
  ranks.push({...identity,accountKey:key,weeklyPoints:points,
    verifiedTaskCompletions:count,lastEarnedAtMs:lastAtMs});
 }
 ranks.sort((a,b)=>b.weeklyPoints-a.weeklyPoints||
   b.verifiedTaskCompletions-a.verifiedTaskCompletions||
   a.lastEarnedAtMs-b.lastEarnedAtMs||
   a.accountKey.localeCompare(b.accountKey,"en"));
 const rows=ranks.slice(0,10).map((r,i)=>({
   place:i+1,
   participantId:"leader-participant-"+createHmac("sha256",backendSecret)
     .update("DEDA_WEEKLY_ACCOUNT|"+r.accountKey).digest("base64url").slice(0,30),
   displayName:r.displayName,activePublicId:r.activePublicId,
   weeklyPoints:r.weeklyPoints,
   verifiedTaskCompletions:r.verifiedTaskCompletions,
   diamondsIfFinalWinner:PRIZES[i],
 }));
 return Object.freeze({
  schema:1,emulatorOnly:true,productionReady:false,
  source:"original_applied_daily_task_receipts_verified_private",
  weekId:week.weekId,status:serverNowMs>=week.closeAtMs?"frozen":"live",
  hasVerifiedServerAppliedXpOnly:true,accountUidIndependent:true,
  updatesOriginalLevelXp:false,creditsDiamonds:false,canGrantPrizes:false,
  rows:Object.freeze(rows),
 });
}
module.exports=Object.freeze({ROSTER,PROOFS,PROJECT,canonicalProofBody,
 seal,projectCanonicalEarnedXpTopTen});
