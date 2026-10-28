"use strict";
/**
 * PRIVATE ONLY: immutable ranking of ACTUAL PRIVATE Firestore weekly task
 * events from original friend-accepted actions, each independently HMAC-
 * signed and source-reviewed in SAME transaction.
 *
 * This is a test of integration/consistency, NOT verified real user XP.
 * Old DEDA mobile task writer is NOT fenced. NO production exports, payouts,
 * identity rights, signed client results, or APK.
 */
const crypto=require("node:crypto");
const {PROJECT,EVENT_ROOT,TALLY_ROOT,ISSUER:EVENT_ISSUER}=
 require("./deda_weekly_original_friend_signed_xp_atomic_shadow_NOT_EXPORTED.js");
const {originalClaim}=require(
 "./deda_weekly_original_friend_accepted_action_NOT_EXPORTED.js");
const {validatePrivateFriendClaimInTransaction}=require(
 "./deda_weekly_original_friend_reviewed_signed_claim_NOT_EXPORTED.js");
const {windowFor,previewFrozenResult,SOURCE,PRIZES}=require(
 "./deda_weekly_stage31_frozen_league_winner_card_NOT_EXPORTED.js");
const {qaId,profilePath,monthOfFinalEligibleInstant}=require(
 "./deda_weekly_stage44_verified_ledger_top10_archive_NOT_EXPORTED.js");
const {dayInIraq}=require(
 "./deda_weekly_xp_atomic_shadow_issuer_NOT_EXPORTED.js");
const ROOT="deda_weekly_private_friend_signed_frozen_top10";
const ISSUER="private_friend_signed_xp_top10_snapshot_QA_ONLY";
const ACCOUNT=/^[0-9]{10,16}$/;
const HEX=/^[a-f0-9]{64}$/;
const DAY=/^20\d{2}-(?:0[1-9]|1[0-2])-(?:0[1-9]|[12]\d|3[01])$/;
const ID=/^@DEDA-[A-Z0-9]{4,12}$/;
const NAME=/^[^\u0000-\u001f\u007f@]{2,60}$/u;
const LIMIT=140; // Deliberately NOT a production scale algorithm.
const fail=why=>{throw Error("DEDA_FRIEND_TOP10_PRIVATE_HOLD_"+why);};
const valid=n=>Number.isSafeInteger(n)&&n>=0;
const obj=s=>s.exists?s.data():null;
const stable=value=>{
 if(value===null||typeof value!=="object")return value;
 if(Array.isArray(value))return value.map(stable);
 return Object.fromEntries(Object.keys(value).sort()
  .map(k=>[k,stable(value[k])]));
};
const digest=(key,value)=>crypto.createHmac("sha256",key)
 .update(JSON.stringify(stable(value))).digest("hex");
const sealed=(key,payload)=>crypto.createHmac("sha256",key)
 .update("DEDA_PRIVATE_FRIEND_FREEZE_TOP10_V1\n")
 .update(JSON.stringify(stable(payload))).digest("hex");
const markerFields=Object.freeze([
 "schema","issuer","emulatorOnly","canAuthorizeProduction",
 "canCreditOriginalXp","canCreditDiamonds","canIssueGift",
 "originalTaskId","action","weekId","accountKey","dayId",
 "eventKey","approvedAtMs","score","eligiblePrivateWeeklyXp",
 "source","acceptedAtMs","recordedAtMs"
]);
function guard(db,backendSecret){
 if(process.env.GCLOUD_PROJECT!==PROJECT||
    process.env.FIRESTORE_EMULATOR_HOST!=="127.0.0.1:8080"||
    process.env.DEDA_FRIEND_REVIEW_EMULATOR_ONLY!=="true"||
    process.env.DEDA_FRIEND_ATOMIC_SHADOW_ONLY!=="true"||
    process.env.DEDA_FRIEND_TOP10_EMULATOR_ONLY!=="true"||
    typeof db?.runTransaction!=="function"||
    typeof db?.collection!=="function"||
    !Buffer.isBuffer(backendSecret)||backendSecret.length<32)
   fail("EMULATOR_ONLY");
}
function markerBody(d){
 if(!d||typeof d!=="object"||Array.isArray(d)||
    Object.keys(d).length!==markerFields.length+1||
    !HEX.test(d.markerSeal||"")||
    !markerFields.every(k=>Object.hasOwn(d,k)))
   fail("INCOMPLETE_OR_EXTRA_EVENT");
 return Object.fromEntries(markerFields.map(k=>[k,d[k]]));
}
function verifyMarker(d,docId,week,now,key){
 const m=markerBody(d);
 if(digest(key,m)==="")fail("IMPOSSIBLE");
 const mac=crypto.createHmac("sha256",key)
  .update("DEDA_PRIVATE_FRIEND_ATOMIC_XP_MARKER_V1\n")
  .update(JSON.stringify(m)).digest("hex");
 // Original writer serializes marker in insertion order. Decode into its
 // fixed original field order, NOT an arbitrary attacker-controlled object.
 if(!crypto.timingSafeEqual(Buffer.from(mac,"hex"),Buffer.from(d.markerSeal,"hex"))||
    m.schema!==1||m.issuer!==EVENT_ISSUER||
    m.emulatorOnly!==true||m.canAuthorizeProduction!==false||
    m.canCreditOriginalXp!==false||m.canCreditDiamonds!==false||
    m.canIssueGift!==false||
    m.originalTaskId!=="long_trip"||m.action!=="friend_accepted"||
    m.source!=="SIGNED_PRIVATE_REVIEW_FIXTURE_NOT_USER_CREDIT"||
    m.weekId!==week.weekId||!ACCOUNT.test(m.accountKey||"")||
    !DAY.test(m.dayId||"")||!HEX.test(m.eventKey||"")||
    m.eventKey!==originalClaim(m.accountKey,m.dayId).eventKey||
    docId!==week.weekId+"_"+m.eventKey||
    !valid(m.recordedAtMs)||m.recordedAtMs>now||
    !valid(m.approvedAtMs)||m.approvedAtMs>m.recordedAtMs||
    m.acceptedAtMs!==m.approvedAtMs||
    m.approvedAtMs<week.openedAtMs||
    m.approvedAtMs>=week.nextOpenMs||
    dayInIraq(m.approvedAtMs)!==m.dayId||
    ![0,20].includes(m.score)||m.eligiblePrivateWeeklyXp!==m.score||
    (m.score===20&&(
      m.approvedAtMs>=week.closeAtMs||
      m.recordedAtMs>=week.closeAtMs))||
    (m.score===0&&m.recordedAtMs<week.closeAtMs))
   fail("UNVERIFIED_SOURCE_OR_BAGHDAD_FREEZE");
 return m;
}
function readOnlySnapshot(data){
 return Object.freeze({...data,
  emulatorOnly:true,productionReady:false,
  realAccountMigrationDone:false,oldApkWriterFenced:false,
  canCreditOriginalXp:false,canCreditDiamonds:false,
  canIssueGift:false,actuallyCreditedDiamonds:0,
  previewOnly:true,readOnly:true});
}
/**
 * Freeze must be requested during Baghdad midnight to 06:00. Queries ALL
 * candidate signed events, validates their original signed claims, compare
 * precise original task tally and read QA profile fixtures, then stores one
 * HMAC sealed private immutable top ten in the SAME Firestore transaction.
 *
 * Replaying changed receipts/profiles NEVER overwrites the frozen result.
 * It must not be exposed to a client as a production rankings endpoint.
 */
async function freezePrivateFriendSignedTopTen({
 db,backendSecret,firstOpenMs,weekIndex,serverNowMs,...overrides
}){
 guard(db,backendSecret);
 if(Object.keys(overrides).length||!valid(serverNowMs)||
    !Number.isSafeInteger(weekIndex))fail("UNTRUSTED_CLIENT_OVERRIDE");
 const week=windowFor(firstOpenMs,weekIndex);
 if(serverNowMs<week.closeAtMs||serverNowMs>=week.nextOpenMs)
  fail("ONLY_BAGHDAD_0000_TO_0600");
 const ref=db.doc(ROOT+"/"+week.weekId);
 return db.runTransaction(async tx=>{
  const previous=obj(await tx.get(ref));
  const snapshots=await tx.get(db.collection(EVENT_ROOT)
   .where("weekId","==",week.weekId).limit(LIMIT+1));
  if(snapshots.size>LIMIT)fail("NOT_SAFE_FOR_PRODUCTION_SCALE");
  const seen=new Set(),accounts=new Map(),source=[];
  const reader={get:async path=>obj(await tx.get(db.doc(path)))};
  for(const snap of snapshots.docs){
   const m=verifyMarker(snap.data(),snap.id,week,serverNowMs,
     backendSecret);
   if(seen.has(m.eventKey))fail("DUPLICATE_SOURCE_EVENT");
   seen.add(m.eventKey);
   // Verify historic signed claim at its own issue/record timestamp,
   // not at freeze midnight (older 5-minute claim must not be reissued).
   const verified=await validatePrivateFriendClaimInTransaction({
    reader,backendSecret,accountKey:m.accountKey,dayId:m.dayId,
    eventKey:m.eventKey,serverNowMs:m.recordedAtMs
   });
   if(verified.approvedAtMs!==m.approvedAtMs)
     fail("CHANGED_ORIGINAL_ACCEPTANCE_AFTER_SIGNING");
   source.push({key:snap.id,seal:snap.data().markerSeal,
     recordedAtMs:m.recordedAtMs});
   if(m.score===0)continue;
   const row=accounts.get(m.accountKey)||{
    accountKey:m.accountKey,weeklyXp:0,verifiedTaskCount:0,reachedAtMs:0
   };
   row.weeklyXp+=20;
   row.verifiedTaskCount++;
   row.reachedAtMs=Math.max(row.reachedAtMs,m.approvedAtMs);
   if(row.verifiedTaskCount>7||row.weeklyXp>140)
     fail("FORGED_OR_DUPLICATED_WEEKLY_TASK");
   accounts.set(m.accountKey,row);
  }
  const records=[];
  for(const row of accounts.values()){
   const t=await reader(TALLY_ROOT+"/"+week.weekId+"_"+row.accountKey);
   if(!t||t.schema!==1||t.issuer!==EVENT_ISSUER||
      t.emulatorOnly!==true||t.canAuthorizeProduction!==false||
      t.canCreditOriginalXp!==false||t.canCreditDiamonds!==false||
      t.canIssueGift!==false||
      t.weekId!==week.weekId||t.accountKey!==row.accountKey||
      t.eligiblePrivateWeeklyXp!==row.weeklyXp||
      t.approvedTaskCount!==row.verifiedTaskCount||
      t.lastOriginalActionAtMs!==row.reachedAtMs)
    fail("MISSING_OR_CHANGED_SIGNED_TALLY");
   const p=await reader(profilePath(row.accountKey,backendSecret));
   if(!p||p.issuer!=="stage44_private_profile_fixture_only"||
      p.emulatorOnly!==true||p.accountKey!==row.accountKey||
      typeof p.displayName!=="string"||!NAME.test(p.displayName)||
      !ID.test(p.activePublicId||"")||
      !Number.isSafeInteger(p.level)||p.level<1||p.level>99999)
    fail("MISSING_PRIVATE_PROFILE_VIEW_FIXTURE");
   records.push({...row,displayName:p.displayName,
    activePublicId:p.activePublicId,level:p.level});
  }
  records.sort((a,b)=>b.weeklyXp-a.weeklyXp||
    b.verifiedTaskCount-a.verifiedTaskCount||
    a.reachedAtMs-b.reachedAtMs||
    a.accountKey.localeCompare(b.accountKey,"en"));
  const leaders=records.slice(0,10).map((r,i)=>({
   place:i+1,participantId:qaId(r.accountKey,backendSecret),
   displayName:r.displayName,activePublicId:r.activePublicId,
   level:r.level,weeklyXp:r.weeklyXp,
   verifiedTaskCount:r.verifiedTaskCount,reachedAtMs:r.reachedAtMs,
   plannedDiamonds:PRIZES[i],
  }));
  const frozen={
   source:SOURCE,emulatorOnly:true,weekId:week.weekId,
   sealedAtMs:previous?.sealedAtMs??serverNowMs,
   rows:leaders.map(r=>({
    place:r.place,participantId:r.participantId,
    weeklyXp:r.weeklyXp,verifiedTaskCount:r.verifiedTaskCount,
    reachedAtMs:r.reachedAtMs,
   }))
  };
  previewFrozenResult({firstOpenMs,weekIndex,serverNowMs,
   snapshot:frozen});
  const payload={
   schema:1,issuer:ISSUER,emulatorOnly:true,
   canAuthorizeProduction:false,canIssueGift:false,
   weekId:week.weekId,closeAtMs:week.closeAtMs,
   releaseAtMs:week.nextOpenMs,sealedAtMs:frozen.sealedAtMs,
   archiveMonthId:monthOfFinalEligibleInstant(week.closeAtMs),
   sourceDigest:digest(backendSecret,source.sort(
     (a,b)=>a.key.localeCompare(b.key,"en"))),
   rankedCount:records.length,topTen:leaders,
   plannedTotalDiamonds:leaders.reduce((s,r)=>s+r.plannedDiamonds,0),
   actuallyCreditedDiamonds:0,
  };
  const signature=sealed(backendSecret,payload);
  if(previous){
   if(previous.signature!==signature||
      JSON.stringify(stable(previous.payload))!==
        JSON.stringify(stable(payload)))
    fail("IMMUTABLE_FREEZE_SOURCE_OR_PROFILE_DRIFT");
   return readOnlySnapshot({
    ...payload,outcome:"already_sealed",
    sealedSignatureVerified:true,
   });
  }
  tx.create(ref,{payload,signature});
  return readOnlySnapshot({
   ...payload,outcome:"frozen_private_snapshot_created",
   sealedSignatureVerified:true,
  });
 },{maxAttempts:5});
}
async function readReleasedPrivateFriendTopTen({
 db,backendSecret,firstOpenMs,weekIndex,serverNowMs,...overrides
}){
 guard(db,backendSecret);
 if(Object.keys(overrides).length||!valid(serverNowMs))
  fail("UNTRUSTED_CLIENT_OVERRIDE");
 const week=windowFor(firstOpenMs,weekIndex);
 if(serverNowMs<week.nextOpenMs)
  fail("WINNERS_NOT_RELEASED_UNTIL_0600_BAGHDAD");
 const saved=await db.doc(ROOT+"/"+week.weekId).get();
 if(!saved.exists)fail("NO_PREVIOUSLY_SEALED_PRIVATE_WEEK");
 const raw=saved.data(),p=raw?.payload;
 if(!p||p.schema!==1||p.issuer!==ISSUER||
    p.emulatorOnly!==true||p.canAuthorizeProduction!==false||
    p.weekId!==week.weekId||p.closeAtMs!==week.closeAtMs||
    p.releaseAtMs!==week.nextOpenMs||
    !valid(p.sealedAtMs)||p.sealedAtMs<week.closeAtMs||
    p.sealedAtMs>=week.nextOpenMs||
    p.actuallyCreditedDiamonds!==0||
    !HEX.test(raw.signature||"")||
    sealed(backendSecret,p)!==raw.signature)
  fail("TAMPERED_OR_UNSEALED_FROZEN_RANKING");
 const snapshot={source:SOURCE,emulatorOnly:true,
  weekId:week.weekId,sealedAtMs:p.sealedAtMs,
  rows:p.topTen.map(r=>({
   place:r.place,participantId:r.participantId,
   weeklyXp:r.weeklyXp,verifiedTaskCount:r.verifiedTaskCount,
   reachedAtMs:r.reachedAtMs
  }))};
 previewFrozenResult({firstOpenMs,weekIndex,serverNowMs,
  snapshot});
 return readOnlySnapshot({...p,outcome:"released_private_preview",
  sealedSignatureVerified:true});
}
module.exports=Object.freeze({
 PROJECT,ROOT,ISSUER,freezePrivateFriendSignedTopTen,
 readReleasedPrivateFriendTopTen
});
