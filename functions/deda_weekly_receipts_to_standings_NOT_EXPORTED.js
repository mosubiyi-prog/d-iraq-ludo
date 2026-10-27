"use strict";

/**
 * Stage10: privileged-server-only READ MODEL / NOT EXPORTED / NO WRITES.
 * Given the future server-owned XP receipts, derive an ordered private weekly
 * snapshot for the existing stage7 privacy-redacting reader. Absent reliable
 * actual XP issuers and live rule verification, output is NOT valid for
 * production or payouts. Raw receipt "issuer" strings can be forged if
 * clients can write the collection: no live deployment of this module now.
 *
 * NO client-submitted events, local XP, phone times, quiz answers, balances,
 * historic levels, manager bonuses, wallets, or diamonds are inputs.
 */
const crypto=require("node:crypto");
const {verifiedWeek}=require("./deda_weekly_leaderboard_shadow_policy.js");
const {opaqueReceiptId}=require("./deda_weekly_owner_receipt_gate_NOT_EXPORTED.js");
const {
  verifyAndRedactSnapshot,scrubDisplayName:neverImport,
}=require("./deda_weekly_snapshot_reader_NOT_EXPORTED.js");
void neverImport;

const XP_ISSUER="privileged_server_only_task_xp_issuer_v1";
const SNAPSHOT_ISSUER="privileged_server_only_weekly_ranker_v1";
const PROFILE_ISSUER="privileged_server_only_public_profile_v1";
const MAX_EVENTS=50000,MAX_PLAYERS=5000;
const ACCOUNT=/^[0-9]{10,16}$/;
const DAY=/^20\d{2}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$/;
const TASK=/^[A-Za-z0-9_:-]{1,100}$/;
const PUBLIC_ID=/^@DEDA-[A-Z0-9]{5,12}$/;
const PRIVACY_NAME=/^[^\u0000-\u001f\u007f@]{2,60}$/u;
const REWARDS=Object.freeze([150,100,50,10,10,10,10,10,10,10]);
function fail(reason){throw Error("DEDA_STAGE10_WEEKLY_RANK_BLOCK_"+reason);}
function integer(n){return Number.isSafeInteger(n)&&n>=0;}
function iraqDay(ms){
  if(!integer(ms))fail("invalid_time");
  const list=new Intl.DateTimeFormat("en-US",{
    timeZone:"Asia/Baghdad",year:"numeric",month:"2-digit",day:"2-digit",
  }).formatToParts(new Date(ms));
  const p=Object.fromEntries(list.map(e=>[e.type,e.value]));
  return p.year+"-"+p.month+"-"+p.day;
}
function requireInternalDb(db){
  if(!db||typeof db.collection!=="function"||typeof db.doc!=="function")
    fail("privileged_admin_store_required");
}
async function readDoc(db,path) {
  const doc=db.doc(path);
  if(!doc||typeof doc.get!=="function")fail("profile_store");
  const snapshot=await doc.get();
  if(!snapshot?.exists||typeof snapshot.data!=="function")
    fail("missing_server_owned_public_profile");
  const data=snapshot.data();
  if(!data||typeof data!=="object"||Array.isArray(data))
    fail("invalid_profile");
  return data;
}
function validateRawReceipt(r,week,nowMs) {
  if(!r||typeof r!=="object"||Array.isArray(r)||
    r.issuer!==XP_ISSUER||r.status!=="final_award_committed"||
    !ACCOUNT.test(r.accountKey||"")||!DAY.test(r.dayId||"")||
    !TASK.test(r.taskId||"")||r.weekId!==week.weekId||
    r.taskPointsAwarded!==true||r.levelXpApplied!==true||
    r.levelXpAmount!==20||!integer(r.verifiedAtMs)||
    r.verifiedAtMs<week.startMs||r.verifiedAtMs>=week.endMs||
    r.verifiedAtMs>nowMs||iraqDay(r.verifiedAtMs)!==r.dayId) {
    fail("unverified_task_xp_receipt");
  }
  const canonical=opaqueReceiptId({
    accountKey:r.accountKey,dayId:r.dayId,taskId:r.taskId,
  });
  if(r.receiptId!==canonical)fail("wrong_canonical_event_key");
  return {accountKey:r.accountKey,verifiedAtMs:r.verifiedAtMs,
    receiptId:r.receiptId};
}
function checkProfile(p,accountKey) {
  if(p.issuer!==PROFILE_ISSUER||p.state!=="verified"||
    p.accountKey!==accountKey||!PUBLIC_ID.test(p.activePublicId||"")||
    !PRIVACY_NAME.test(p.displayName||"")||
    /\b0[0-9]{10}\b/.test(p.displayName)||
    /\S+@\S+/.test(p.displayName))fail("unsafe_public_profile");
  return {activePublicId:p.activePublicId,displayName:p.displayName};
}
/**
 * Needs a 32-byte PRIVATE backend HMAC secret, never user or Flutter input.
 * A salted opaque ID cannot be brute-forced like SHA256(phone).
 */
function competitorId(accountKey,rankerKey){
  if(!Buffer.isBuffer(rankerKey)||rankerKey.length<32)
    fail("private_ranker_secret_missing");
  return "leader-participant-"+crypto.createHmac("sha256",rankerKey)
    .update(accountKey,"utf8").digest("base64url").slice(0,30);
}

/**
 * Query structure works with Firebase Admin SDK if future receipt collection
 * exists; also testable with an in-memory stub. Still ZERO Firestore writes.
 * "previous" snapshot is marked CLOSED, never displays post-close claims.
 */
async function projectFutureServerWeek({
  db,weekConfig,serverNowMs,rankerKey,kind,
}) {
  requireInternalDb(db);
  if(!integer(serverNowMs))fail("server_clock");
  const week=verifiedWeek(weekConfig);
  if(!["current","previous"].includes(kind))fail("week_mode");
  if(serverNowMs<week.startMs)fail("week_not_started");
  if(kind==="current"&&serverNowMs>=week.endMs)fail("active_week_closed");
  if(kind==="previous"&&serverNowMs<week.endMs)fail("previous_week_open");
  // Validate secret BEFORE performing reads. No client provides this value.
  competitorId("07700000000",rankerKey);
  const base=db.collection("deda_weekly_xp_receipts")
    .doc(week.weekId).collection("events");
  const snap=await base.get();
  if(!snap||!Array.isArray(snap.docs)||snap.docs.length>MAX_EVENTS)
    fail("invalid_receipt_query");
  const rows=new Map(),seen=new Set();
  for(const document of snap.docs){
    if(!document||typeof document.data!=="function")fail("bad_receipt_doc");
    const receipt=document.data();
    const checked=validateRawReceipt(receipt,week,serverNowMs);
    if(document.id!==checked.receiptId||seen.has(checked.receiptId))
      fail("duplicated_or_wrong_receipt_document");
    seen.add(checked.receiptId);
    const row=rows.get(checked.accountKey)||{
      accountKey:checked.accountKey,taskClaims:0,
      earnedLevelXp:0,lastEarnedAtMs:0,
    };
    row.taskClaims++;
    row.earnedLevelXp+=20;
    row.lastEarnedAtMs=Math.max(row.lastEarnedAtMs,checked.verifiedAtMs);
    if(!integer(row.earnedLevelXp))fail("xp_overflow");
    rows.set(checked.accountKey,row);
    if(rows.size>MAX_PLAYERS)fail("too_many_competitors");
  }
  const sorted=[...rows.values()].sort((a,b)=>
    b.earnedLevelXp-a.earnedLevelXp||
    b.taskClaims-a.taskClaims||
    a.lastEarnedAtMs-b.lastEarnedAtMs||
    (a.accountKey<b.accountKey?-1:a.accountKey>b.accountKey?1:0));
  const activeIds=new Set();
  const ranking=[];
  // Fetch future privileged public profile only for accounts that truly
  // earned verified XP. No arbitrary user query, no phone in public response.
  for(let i=0;i<sorted.length;i++){
    const score=sorted[i];
    const profileHash=crypto.createHash("sha256")
      .update(score.accountKey,"utf8").digest("hex");
    const profile=checkProfile(await readDoc(db,
      "deda_weekly_public_profiles/"+profileHash),score.accountKey);
    if(activeIds.has(profile.activePublicId))fail("duplicate_public_id");
    activeIds.add(profile.activePublicId);
    ranking.push(Object.freeze({
      place:i+1,accountKey:score.accountKey,
      publicCompetitorId:competitorId(score.accountKey,rankerKey),
      activePublicId:profile.activePublicId,
      displayName:profile.displayName,
      earnedLevelXp:score.earnedLevelXp,
      taskClaims:score.taskClaims,
      lastEarnedAtMs:score.lastEarnedAtMs,
      potentialDiamonds:REWARDS[i]||0,
    }));
  }
  const generatedAtMs=kind==="previous"?
      week.endMs-1:serverNowMs;
  const result=Object.freeze({
    issuer:SNAPSHOT_ISSUER,
    state:kind==="current"?"live":"closed",
    weekId:week.weekId,generatedAtMs,
    rows:Object.freeze(ranking),
  });
  // Execute the same mandatory stage7 reader validation to ensure ranking
  // can be redacted and consumed. Raw private snapshot never goes to client.
  verifyAndRedactSnapshot(result,week,"0000000000",serverNowMs,kind);
  return result;
}
module.exports=Object.freeze({
  projectFutureServerWeek,validateRawReceipt,competitorId,
});
