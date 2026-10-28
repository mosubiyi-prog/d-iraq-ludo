"use strict";
/**
 * Stage63: REAL LOCAL FIRESTORE TRANSACTION across the existing
 * Stage43/44 applied progress receipts and Stage46 independently signed,
 * reviewer-authorized XP claims. One frozen immutable PRIVATE QA snapshot.
 *
 * This is an AUTHORITATIVE CONSISTENCY REHEARSAL of synthetic source records,
 * NOT an independently certified original mobile user score or production
 * winner. All payout, credits, migration and public-release flags FALSE.
 *
 * Crucially Stage46 claim signatures have 5-minute ISSUANCE windows. Frozen
 * result must validate their signatures at historical ORIGINAL ISSUE time
 * while also verifying every underlying original record in a single CURRENT
 * Firestore transaction. A stale/current production claim cannot be minted.
 */
const crypto=require("node:crypto");
const core=require("../progress_archive/reconcile-core.cjs");
const {PROJECT,ISSUER:SOURCE_ISSUER,ROOT:SOURCE_ROOT,receiptFor}=
 require("../../../functions/deda_weekly_stage42_server_share_action_producer_NOT_EXPORTED.js");
const {ROOT:EPOCH_ROOT,ISSUER:EPOCH_ISSUER}=
 require("../../../functions/deda_weekly_stage43_reviewed_cutover_epoch_NOT_EXPORTED.js");
const {LEAGUE_ROOT}=require(
 "../../../functions/deda_weekly_stage43_cutover_epoch_atomic_NOT_EXPORTED.js");
const {qaId,profilePath}=require(
 "../../../functions/deda_weekly_stage44_verified_ledger_top10_archive_NOT_EXPORTED.js");
const {validateSignedTaskClaimInTransaction}=require(
 "../../../functions/deda_weekly_stage46_private_signed_task_claim_NOT_EXPORTED.js");
const {windowFor,PRIZES}=require(
 "../../../functions/deda_weekly_stage31_frozen_league_winner_card_NOT_EXPORTED.js");
const {BINDING_ROOT,verifiedBind}=require(
 "../stage62/private_account_bound_signed_xp_reader.cjs");
const ROOT="deda_weekly_stage63_private_immutable_frozen_xp_snapshots";
const FORMAT=1,ACCOUNT=/^[0-9]{10,16}$/;
const fail=reason=>{throw Error("DEDA_STAGE63_HOLD_"+reason);};
const val=s=>s.exists?s.data():null;
const hmac=(key,raw)=>crypto.createHmac("sha256",key)
 .update(raw).digest("hex");
const sorted=value=>{
 if(value===null||typeof value!=="object")return value;
 if(Array.isArray(value))return value.map(sorted);
 return Object.fromEntries(Object.keys(value).sort()
  .map(k=>[k,sorted(value[k])]));
};
const sign=(key,record)=>hmac(key,JSON.stringify(sorted(record)));
function guard({db,backendSecret,authUid}){
 if(process.env.GCLOUD_PROJECT!==PROJECT||
    process.env.FIRESTORE_EMULATOR_HOST!=="127.0.0.1:8080"||
    process.env.FIREBASE_AUTH_EMULATOR_HOST!=="127.0.0.1:9099"||
    process.env.FIREBASE_FUNCTIONS_EMULATOR_HOST!=="127.0.0.1:5001"||
    process.env.DEDA_STAGE63_EMULATOR_ONLY!=="true"||
    typeof db?.runTransaction!=="function"||
    typeof db?.collection!=="function"||
    !Buffer.isBuffer(backendSecret)||backendSecret.length<32||
    !/^[A-Za-z0-9_-]{8,128}$/.test(authUid||""))
   fail("EMULATOR_ONLY_UNTRUSTED_SESSION");
}
function safeRow(r,week){
 if(!r||Object.keys(r).length!==9||
    r.issuer!==SOURCE_ISSUER||r.emulatorOnly!==true||
    !ACCOUNT.test(r.accountKey||"")||
    r.weekId!==week.weekId||
    r.taskId!=="share_personal_location"||
    r.amount!==20||
    !/^[0-9a-f]{64}$/.test(r.eventKey||"")||
    !/^20\d{2}-\d{2}-\d{2}$/.test(r.dayId||"")||
    !Number.isSafeInteger(r.createdAtMs)||
    r.createdAtMs<week.openedAtMs||r.createdAtMs>=week.closeAtMs)
   fail("UNTRUSTED_SOURCE_WEEKLY_EVENT");
}
function immutableResult(base,viewerParticipantId){
 const viewer=base.rows.find(r=>r.participantId===viewerParticipantId);
 return Object.freeze({
  source:"STAGE63_PRIVATE_TRANSACTION_SEALED_FIXTURE_ONLY",schema:1,
  emulatorOnly:true,verified:false,productionReady:false,
  productionAppCheckVerified:false,oldApkWriterFenced:false,
  realAccountMigrationDone:false,canCreditDiamonds:false,
  canIssueGift:false,canWriteXp:false,canTransferWallet:false,
  canReplacePremiumId:false,originalQuizChanged:false,
  immutableQaSnapshot:true,readOnly:true,
  state:"FROZEN_PRIVATE_HOLD",weekId:base.weekId,
  closeAtMs:base.closeAtMs,releaseAtMs:base.releaseAtMs,
  viewerPlace:viewer?.place??null,viewerWeeklyXp:viewer?.weeklyXp??0,
  topTen:base.rows,plannedTotalDiamonds:base.rows.reduce(
   (s,r)=>s+r.plannedDiamonds,0),actuallyCreditedDiamonds:0
 });
}
/**
 * Returns only after a genuine transaction has validated ALL currently
 * present original applied receipts, independent signed task claim and
 * profile. The deterministic private snapshot is never overwritten. Repeated
 * requests recompute source digest and refuse any source/tampered snapshot.
 */
async function freezeAccountBoundPrivateWeek({
 db,authUid,backendSecret,firstOpenMs,weekIndex,serverNowMs,...extra
}){
 guard({db,authUid,backendSecret});
 if(Object.keys(extra).length||
    !Number.isSafeInteger(serverNowMs)||!Number.isSafeInteger(weekIndex)||
    !Number.isSafeInteger(firstOpenMs))fail("UNTRUSTED_CLIENT_OVERRIDE");
 const week=windowFor(firstOpenMs,weekIndex);
 if(serverNowMs<week.closeAtMs||serverNowMs>=week.nextOpenMs)
   fail("OUTSIDE_BAGHDAD_MIDNIGHT_TO_0600_FREEZE");
 const docId=hmac(backendSecret,"frozen-week|"+week.weekId);
 const frozenRef=db.doc(ROOT+"/"+docId);
 return db.runTransaction(async tx=>{
  const read=async path=>val(await tx.get(db.doc(path)));
  const binding=await read(BINDING_ROOT+"/"+authUid);
  let account;
  try{account=verifiedBind(binding,authUid,backendSecret);}
  catch(e){fail("NOT_SAME_VERIFIED_FIXTURE_ACCOUNT");}
  const all=await tx.get(db.collection(LEAGUE_ROOT).where(
   "weekId","==",week.weekId));
  if(all.size>5000)fail("TOO_MANY_WEEKLY_EVENTS");
  const seen=new Set(),sums=new Map(),evidence=[];
  for(const snap of all.docs){
   const r=snap.data();
   safeRow(r,week);
   if(snap.id!==week.weekId+"_"+r.eventKey||
      seen.has(r.eventKey))fail("DUPLICATE_OR_FORGED_EVENT");
   seen.add(r.eventKey);
   const [source,migration,epoch,claimed,applied,state]=await Promise.all([
    read(SOURCE_ROOT+"/"+r.eventKey),
    read("deda_progress_migrations/"+r.accountKey),
    read(EPOCH_ROOT+"/"+r.accountKey),
    read("deda_progress_receipts/"+r.accountKey+"/events/"+r.eventKey),
    read("deda_verified_progress/"+r.accountKey+"/events/"+r.eventKey),
    read("deda_verified_progress/"+r.accountKey)
   ]);
   if(!source||!migration||!epoch||!claimed||!applied||!state||
      source.issuer!==SOURCE_ISSUER||source.emulatorOnly!==true||
      source.canAuthorizeProduction!==false||
      source.serverVerifiedAction!==true||
      source.accountKey!==r.accountKey||source.dayId!==r.dayId||
      source.taskId!=="share_personal_location"||
      source.eventKey!==r.eventKey||
      source.originalLocalClaimAwarded!==
       "UNKNOWN_REQUIRES_MIGRATION_REVIEW"||
      source.verifiedAs!=="original_cross_account_share_action_only"||
      !Number.isSafeInteger(source.sourceCreatedAtMs)||
      source.sourceCreatedAtMs<week.openedAtMs||
      source.sourceCreatedAtMs>=week.closeAtMs||
      source.sourceCreatedAtMs>r.createdAtMs||
      source.xpGranted!==0||source.pointsGranted!==0||
      source.coinsGranted!==0||source.diamondsGranted!==0||
      epoch.issuer!==EPOCH_ISSUER||epoch.emulatorOnly!==true||
      epoch.canAuthorizeProduction!==false||
      epoch.realOldApkRevocationVerified!==false||
      epoch.accountKey!==r.accountKey||
      epoch.migrationId!==migration.migrationId||
      epoch.evidenceDigest!==migration.evidenceDigest||
      epoch.baselineEventKey!==migration.baselineEventKey||
      epoch.settlementId!==migration.settlementId||
      epoch.pendingLocalClaims!==0||epoch.pendingPurchases!==0||
      epoch.pendingReservations!==0||
      epoch.phase!=="reviewed-server-only-private-fixture"||
      migration.phase!=="cutover-complete")
     fail("INCONSISTENT_ORIGINAL_SOURCE_OR_CUTOVER");
   let canonical;
   try{
    const expected=receiptFor(r.accountKey,r.dayId);
    canonical=core.parseReceipt(claimed,r.accountKey);
    const appliedReceipt=core.parseReceipt(applied.receipt,r.accountKey);
    const status=core.parseState(state,r.accountKey);
    if(r.eventKey!==expected.eventKey||
       !core.sameEvent(expected.receipt,canonical)||
       !core.sameEvent(canonical,appliedReceipt)||
       applied.eventKey!==r.eventKey||
       applied.receiptId!==r.eventKey||
       applied.emitter!=="stage43_private_reviewed_cutover_atomic_emulator_only"||
       !Number.isSafeInteger(applied.appliedVersion)||
       applied.appliedVersion<2||
       status.version<applied.appliedVersion)
      fail("XP_NOT_APPLIED_TO_ORIGINAL_LEDGER");
   }catch(_){fail("XP_NOT_APPLIED_TO_ORIGINAL_LEDGER");}
   // Stage46 receipt is valid for five minutes from ISSUE, not seven days.
   // For historical freeze revalidation, check the independent HMAC/reviewer
   // at the recorded issue instant IN THIS TRANSACTION, not with fake today
   // freshness. Server week-time is checked separately above.
   const issueAt=r.createdAtMs+100;
   try{
    await validateSignedTaskClaimInTransaction({
     reader:{get:read},accountKey:r.accountKey,
     dayId:r.dayId,eventKey:r.eventKey,
     originalShareId:source.originalShareId,
     sourceCreatedAtMs:source.sourceCreatedAtMs,
     serverNowMs:issueAt,migrationId:migration.migrationId,
     backendSecret
    });
   }catch(_){fail("REVIEWED_SIGNED_TASK_XP_MISSING");}
   const prior=sums.get(r.accountKey)||{
    accountKey:r.accountKey,weeklyXp:0,verifiedTaskCount:0,
    reachedAtMs:0
   };
   prior.weeklyXp+=20;
   prior.verifiedTaskCount++;
   prior.reachedAtMs=Math.max(prior.reachedAtMs,source.sourceCreatedAtMs);
   if(!Number.isSafeInteger(prior.weeklyXp))fail("XP_OVERFLOW");
   sums.set(r.accountKey,prior);
   evidence.push({accountDigest:hmac(backendSecret,"account:"+r.accountKey),
    eventKey:r.eventKey,issueAt,
    receiptHash:sign(backendSecret,claimed),
    appliedHash:sign(backendSecret,applied),
    sourceHash:sign(backendSecret,source),
    epochHash:sign(backendSecret,epoch),
    progressHash:sign(backendSecret,state)});
  }
  const sortedRows=[...sums.values()].sort((a,b)=>
   b.weeklyXp-a.weeklyXp||
   b.verifiedTaskCount-a.verifiedTaskCount||
   a.reachedAtMs-b.reachedAtMs||
   a.accountKey.localeCompare(b.accountKey,"en"));
  const topTen=[];
  for(const [i,r] of sortedRows.slice(0,10).entries()){
   const profile=await read(profilePath(r.accountKey,backendSecret));
   if(!profile||profile.issuer!=="stage44_private_profile_fixture_only"||
      profile.emulatorOnly!==true||
      profile.accountKey!==r.accountKey||
      typeof profile.displayName!=="string"||
      profile.displayName.length<2||
      !/^@DEDA-[A-Z0-9]{4,12}$/.test(profile.activePublicId||"")||
      !Number.isSafeInteger(profile.level)||profile.level<1)
     fail("UNTRUSTED_PLAYER_PROFILE");
   topTen.push({
    place:i+1,participantId:qaId(r.accountKey,backendSecret),
    displayName:profile.displayName,
    activePublicId:profile.activePublicId,level:profile.level,
    weeklyXp:r.weeklyXp,verifiedTaskCount:r.verifiedTaskCount,
    plannedDiamonds:PRIZES[i],reachedAtMs:r.reachedAtMs
   });
   evidence.push({participantId:topTen.at(-1).participantId,
    profileHash:sign(backendSecret,profile)});
  }
  evidence.sort((a,b)=>JSON.stringify(a).localeCompare(JSON.stringify(b)));
  const sourceDigest=sign(backendSecret,{
   weekId:week.weekId,sourceEvidence:evidence,
   rowData:topTen,originalSourceCount:all.size
  });
  const record={
   format:FORMAT,source:"STAGE63_ORIGINAL_SIGNED_XP_EMULATOR_ONLY",
   emulatorOnly:true,productionReady:false,
   canCreditDiamonds:false,canIssueGift:false,canWriteXp:false,
   canTransferWallet:false,
   state:"FROZEN_PRIVATE_HOLD",
   weekId:week.weekId,closeAtMs:week.closeAtMs,
   releaseAtMs:week.nextOpenMs,sourceDigest,
   rows:topTen,sourceEventCount:all.size,
   frozenRecordedAtMs:serverNowMs
  };
  const existing=await tx.get(frozenRef);
  if(existing.exists){
   const old=existing.data();
   if(!old||old.format!==FORMAT||
      old.source!==record.source||
      old.emulatorOnly!==true||old.productionReady!==false||
      old.canCreditDiamonds!==false||
      old.canIssueGift!==false||old.canWriteXp!==false||
      old.canTransferWallet!==false||
      old.state!==record.state||old.weekId!==record.weekId||
      old.closeAtMs!==record.closeAtMs||
      old.releaseAtMs!==record.releaseAtMs||
      old.sourceDigest!==record.sourceDigest||
      old.sourceEventCount!==record.sourceEventCount||
      !Number.isSafeInteger(old.frozenRecordedAtMs)||
      old.frozenRecordedAtMs<week.closeAtMs||
      old.frozenRecordedAtMs>=week.nextOpenMs||
      JSON.stringify(old.rows)!==JSON.stringify(record.rows))
     fail("ORIGINAL_SOURCE_CHANGED_AFTER_FREEZE_OR_SEAL_TAMPERED");
   return immutableResult(old,qaId(account,backendSecret));
  }
  tx.create(frozenRef,record);
  return immutableResult(record,qaId(account,backendSecret));
 },{maxAttempts:5});
}
module.exports={PROJECT,ROOT,freezeAccountBoundPrivateWeek};
