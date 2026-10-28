"use strict";

/**
 * DEDA Stage29 — end-to-end IN-MEMORY / FIRESTORE EMULATOR ONLY.
 *
 * Connects Stage9's atomic simulated +20 XP task receipts to a single
 * normalized weekly rank projection. The same snapshot is returned to a
 * competitor and to an owner dashboard MOCK, with no fictitious player
 * names and no prize payout. Deliberately NEVER emits the production
 * issuer strings required by Stage7/Stage10. Cannot run in real Firebase.
 *
 * This integration is evidence of schema and ordering compatibility ONLY,
 * not evidence of real cross-device task XP, certified account sessions,
 * Firestore rules, GM approval or spendable rewards. NOT EXPORTED by index.js.
 */
const crypto = require("node:crypto");
const {PROJECT, ROOT, XP_PER_TASK, dayInIraq} =
  require("./deda_weekly_xp_atomic_shadow_issuer_NOT_EXPORTED.js");
const {verifiedWeek} =
  require("./deda_weekly_leaderboard_shadow_policy.js");
const {opaqueReceiptId, resolveFutureVerifiedAccount} =
  require("./deda_weekly_owner_receipt_gate_NOT_EXPORTED.js");

const ISSUER = "emulator_only_weekly_rank_projection_v1";
const RECEIPT_ISSUER = "emulator_only_weekly_xp_shadow_v1";
const MAX_RECEIPTS=50000,MAX_PLAYERS=5000,MAX_TASKS_PER_DAY=8;
const REWARDS=Object.freeze([150,100,50,10,10,10,10,10,10,10]);
const ACCOUNT=/^[0-9]{10,16}$/;
const TASK=/^[A-Za-z0-9_:-]{1,100}$/;
const DAY=/^20\d{2}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$/;

function fail(code) {throw Error("DEDA_STAGE29_SHADOW_INTEGRATION_BLOCK_"+code);}
function integer(n){return Number.isSafeInteger(n)&&n>=0;}
function requireEmulator(db) {
  if(process.env.GCLOUD_PROJECT!==PROJECT ||
    !process.env.FIRESTORE_EMULATOR_HOST ||
    !db || typeof db.collection!=="function" ||
    typeof db.doc!=="function")fail("emulator_only");
}
function token(account,secret) {
  if(!Buffer.isBuffer(secret)||secret.length<32)fail("backend_secret_missing");
  return "qa-player-"+crypto.createHmac("sha256",secret)
    .update(account,"utf8").digest("base64url").slice(0,25);
}
function oneReceipt(doc,week,nowMs) {
  if(!doc || typeof doc.id!=="string"||typeof doc.data!=="function")
    fail("invalid_receipt_document");
  const r=doc.data();
  if(!r||typeof r!=="object"||Array.isArray(r)||
    doc.id!==r.eventId||r.issuer!==RECEIPT_ISSUER||
    r.shadowOnly!==true||!ACCOUNT.test(r.accountKey||"")||
    !TASK.test(r.taskId||"")||!DAY.test(r.dayId||"")||
    r.weekId!==week.weekId||r.amount!==XP_PER_TASK||
    !integer(r.verifiedAtMs)||!integer(r.createdAtMs)||
    r.verifiedAtMs<week.startMs||r.verifiedAtMs>=week.endMs||
    r.verifiedAtMs>nowMs||r.createdAtMs<r.verifiedAtMs||
    r.createdAtMs>nowMs||dayInIraq(r.verifiedAtMs)!==r.dayId||
    r.eventId!==opaqueReceiptId({
      accountKey:r.accountKey,dayId:r.dayId,taskId:r.taskId,
    })) fail("untrusted_shadow_receipt");
  return r;
}
/** No client-supplied scores, names, ranks, week time or award amounts. */
async function previewWeekFromAtomicShadowXp({
  db,weekConfig,serverNowMs,backendSecret,request,
}) {
  requireEmulator(db);
  if(!integer(serverNowMs))fail("invalid_server_time");
  const week=verifiedWeek(weekConfig);
  if(serverNowMs<week.startMs)fail("week_not_started");
  // Resolve the canonical original account, never the displayed premium ID.
  const owner=await resolveFutureVerifiedAccount({
    db,request,serverNowMs,
  });
  token(owner.canonicalAccountKey,backendSecret);
  const collection=db.collection(ROOT.receipt);
  if(!collection||typeof collection.get!=="function")
    fail("shadow_receipt_reader_missing");
  const snap=await collection.get();
  if(!snap || !Array.isArray(snap.docs)||snap.docs.length>MAX_RECEIPTS)
    fail("oversized_shadow_receipts");
  const records=new Map(),ids=new Set(),days=new Map();
  for(const d of snap.docs) {
    const r=d.data();
    // Historical receipts from another week are isolated rather than
    // being promoted into the active week; no client-configured week.
    if(r?.weekId!==week.weekId)continue;
    const x=oneReceipt(d,week,serverNowMs);
    if(ids.has(x.eventId))fail("duplicate_receipt");
    ids.add(x.eventId);
    const dkey=x.accountKey+"|"+x.dayId;
    const daily=(days.get(dkey)||0)+1;
    if(daily>MAX_TASKS_PER_DAY)fail("too_many_daily_tasks");
    days.set(dkey,daily);
    const row=records.get(x.accountKey)||{
      accountKey:x.accountKey,earnedLevelXp:0,taskClaims:0,
      lastEarnedAtMs:0,
    };
    row.earnedLevelXp+=XP_PER_TASK;row.taskClaims+=1;
    row.lastEarnedAtMs=Math.max(row.lastEarnedAtMs,x.verifiedAtMs);
    if(!integer(row.earnedLevelXp)||!integer(row.taskClaims))
      fail("score_overflow");
    records.set(x.accountKey,row);
    if(records.size>MAX_PLAYERS)fail("too_many_players");
  }
  const sorted=[...records.values()].sort((a,b)=>
    b.earnedLevelXp-a.earnedLevelXp ||
    b.taskClaims-a.taskClaims ||
    a.lastEarnedAtMs-b.lastEarnedAtMs ||
    (a.accountKey<b.accountKey?-1:a.accountKey>b.accountKey?1:0));
  const rows=sorted.map((r,i)=>Object.freeze({
    place:i+1,
    participantId:token(r.accountKey,backendSecret),
    weeklyXp:r.earnedLevelXp,
    verifiedTaskCount:r.taskClaims,
    // Estimate only — no diamonds may be granted from this preview.
    plannedPrizeDiamonds:REWARDS[i]||0,
  }));
  const safeRows=Object.freeze(rows);
  const viewerIndex=sorted.findIndex(x=>x.accountKey===owner.canonicalAccountKey);
  // Same immutable ordered rows are consumed by BOTH preview surfaces.
  return Object.freeze({
    issuer:ISSUER,previewOnly:true,verifiedRealXp:false,
    payoutEnabled:false,adminAuthorizationVerified:false,
    weekId:week.weekId,state:serverNowMs>=week.endMs?"closed":"active",
    rows:safeRows,
    competitorView:Object.freeze({
      rows:Object.freeze(safeRows.slice(0,10)),
      myRank:viewerIndex<0?null:viewerIndex+1,
      myParticipantId:viewerIndex<0?null:rows[viewerIndex].participantId,
    }),
    managerPreview:Object.freeze({
      rows:safeRows,
      approvalEnabled:false,
    }),
  });
}
module.exports=Object.freeze({
  PROJECT,ISSUER,previewWeekFromAtomicShadowXp,
});
