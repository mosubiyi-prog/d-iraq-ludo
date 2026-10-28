"use strict";
/**
 * Stage44: READ-ONLY verified-progress receipt -> TOP TEN / midnight freeze /
 * GM monthly preview, using STAGE43's original local-emulator ledger.
 *
 * IMPORTANT: no Cloud Function export, no production issuer, no real gift
 * receipt, no release to clients. All issuer/provenance is emulator fixtures;
 * a synthetic document is NOT independent proof of real user XP. The output
 * is PRIVATE audit data, not a signed, immutable, production ranking.
 * The current original mobile XP/point writer still needs real migration.
 */
const crypto=require("node:crypto");
const core=require("../tools/app_stability/progress_archive/reconcile-core.cjs");
const {PROJECT,dayInIraq}=require(
  "./deda_weekly_xp_atomic_shadow_issuer_NOT_EXPORTED.js");
const {windowFor,previewFrozenResult,clockState,SOURCE,PRIZES}=require(
  "./deda_weekly_stage31_frozen_league_winner_card_NOT_EXPORTED.js");
const {LEAGUE_ROOT}=require(
  "./deda_weekly_stage43_cutover_epoch_atomic_NOT_EXPORTED.js");
const {ROOT:SOURCE_ROOT,ISSUER:SOURCE_ISSUER,receiptFor}=require(
  "./deda_weekly_stage42_server_share_action_producer_NOT_EXPORTED.js");
const {ROOT:EPOCH_ROOT,ISSUER:EPOCH_ISSUER}=require(
  "./deda_weekly_stage43_reviewed_cutover_epoch_NOT_EXPORTED.js");

const ACCOUNT=/^[0-9]{10,16}$/;
const DAY=/^20\d{2}-(?:0[1-9]|1[0-2])-(?:0[1-9]|[12]\d|3[01])$/;
const NAME=/^[^\u0000-\u001f\u007f@]{2,60}$/u;
const PUBLIC_ID=/^@DEDA-[A-Z0-9]{4,12}$/;
const VERIFIED_ROOT="deda_weekly_stage44_private_public_profile_fixtures";
const MAX_EVENT_ROWS=5000;
function fail(code){throw Error("DEDA_STAGE44_PREVIEW_BLOCK_"+code);}
function ms(x){return Number.isSafeInteger(x)&&x>=0;}
function text(x,re){return typeof x==="string"&&re.test(x);}
function requireLocal(db,secret){
  if(process.env.GCLOUD_PROJECT!==PROJECT||
     !process.env.FIRESTORE_EMULATOR_HOST||
     !db||typeof db.collection!=="function"||
     typeof db.doc!=="function"||
     !Buffer.isBuffer(secret)||secret.length<32)
    fail("private_emulator_only");
}
function qaId(account,secret){
  return "qa-player-"+crypto.createHmac("sha256",secret)
    .update(account).digest("base64url").slice(0,25);
}
function profilePath(account,secret){
  return VERIFIED_ROOT+"/"+crypto.createHmac("sha256",secret)
    .update("profile|"+account).digest("hex");
}
function monthOfFinalEligibleInstant(closeAtMs){
  if(!ms(closeAtMs)||closeAtMs<1)fail("invalid_close");
  return dayInIraq(closeAtMs-1).slice(0,7);
}
function checkSource(source,original,record,week,serverNowMs){
  if(!source||
     source.issuer!==SOURCE_ISSUER||
     source.emulatorOnly!==true||
     source.canAuthorizeProduction!==false||
     source.serverVerifiedAction!==true||
     source.verifiedAs!=="original_cross_account_share_action_only"||
     source.originalLocalClaimAwarded!=="UNKNOWN_REQUIRES_MIGRATION_REVIEW"||
     source.accountKey!==record.accountKey||
     source.dayId!==record.dayId||
     source.eventKey!==record.eventKey||
     source.taskId!=="share_personal_location"||
     !ms(source.sourceCreatedAtMs)||
     source.sourceCreatedAtMs<week.openedAtMs||
     source.sourceCreatedAtMs>=week.closeAtMs||
     source.sourceCreatedAtMs>record.createdAtMs||
     source.sourceCreatedAtMs>serverNowMs||
     source.coinsGranted!==0||source.xpGranted!==0||
     source.pointsGranted!==0||source.diamondsGranted!==0||
     dayInIraq(source.sourceCreatedAtMs)!==record.dayId||
     !source.originalShareId||typeof source.originalShareId!=="string"||
     source.originalShareId.length!==20||
     !original||original.receiptId!==record.eventKey||
     original.eventKey!==record.eventKey||
     original.emitter!=="stage43_private_reviewed_cutover_atomic_emulator_only"||
     original.accountKey!==record.accountKey||
     !ms(original.appliedVersion)||
     original.appliedVersion<2)
    fail("unverified_applied_original_event");
  return source.sourceCreatedAtMs;
}
async function verifyPairedReceipt(db,row,week,serverNowMs){
  if(!row||Object.keys(row).length!==9||
     row.issuer!==SOURCE_ISSUER||
     row.emulatorOnly!==true||
     !text(row.accountKey,ACCOUNT)||
     row.weekId!==week.weekId||
     !text(row.dayId,DAY)||
     row.taskId!=="share_personal_location"||
     row.amount!==20||
     !ms(row.createdAtMs)||
     row.createdAtMs>serverNowMs)
    fail("incorrect_league_receipt");
  const {eventKey,receipt}=receiptFor(row.accountKey,row.dayId);
  if(row.eventKey!==eventKey)fail("wrong_original_event_key");
  const base="deda_verified_progress/"+row.accountKey;
  const [claimed,applied,source,state,epoch,migration]=await Promise.all([
    db.doc("deda_progress_receipts/"+row.accountKey+
      "/events/"+eventKey).get(),
    db.doc(base+"/events/"+eventKey).get(),
    db.doc(SOURCE_ROOT+"/"+eventKey).get(),
    db.doc(base).get(),
    db.doc(EPOCH_ROOT+"/"+row.accountKey).get(),
    db.doc("deda_progress_migrations/"+row.accountKey).get(),
  ]);
  if(!claimed.exists||!applied.exists||!source.exists||
     !state.exists||!epoch.exists||!migration.exists)
    fail("orphan_league_receipt");
  const claimedReceipt=core.parseReceipt(claimed.data(),row.accountKey);
  const appliedDoc=applied.data();
  if(!core.sameEvent(claimedReceipt,receipt)||
     !core.sameEvent(core.parseReceipt(appliedDoc.receipt,row.accountKey),receipt))
    fail("receipt_not_applied_to_original_progress");
  const original=appliedDoc;
  const created=checkSource(source.data(),original,row,week,serverNowMs);
  const stateVal=core.parseState(state.data(),row.accountKey);
  const ep=epoch.data(),m=migration.data();
  if(stateVal.version<original.appliedVersion||
     ep.issuer!==EPOCH_ISSUER||ep.emulatorOnly!==true||
     ep.canAuthorizeProduction!==false||
     ep.accountKey!==row.accountKey||
     ep.migrationId!==m.migrationId||
     ep.evidenceDigest!==m.evidenceDigest||
     ep.baselineEventKey!==m.baselineEventKey||
     ep.settlementId!==m.settlementId||
     ep.realOldApkRevocationVerified!==false||
     ep.phase!=="reviewed-server-only-private-fixture"||
     ep.pendingLocalClaims!==0||
     ep.pendingPurchases!==0||
     ep.pendingReservations!==0||
     !ms(ep.effectiveAtMs)||ep.effectiveAtMs>created||
     m.phase!=="cutover-complete")
    fail("cutover_or_verified_progress_conflict");
  return {accountKey:row.accountKey,dayId:row.dayId,
    eventKey,sourceCreatedAtMs:created};
}

/**
 * No client input, no mutable weekly totals and no payout. Read only one
 * authorized demo-collection week, cross-check every receipt with the
 * canonical ORIGINAL applied XP event, its source action and migration epoch.
 *
 * Ranking is a consistent TEST snapshot only in the absence of concurrent
 * writes. Production requires privileged snapshot sealing in a transaction
 * or versioned score aggregation, secure profiles and hard-authenticated
 * backend receipts.
 */
async function previewPrivateTopTenFromAppliedXp({
  db,firstOpenMs,weekIndex,serverNowMs,backendSecret,
  ...overrides
}){
  requireLocal(db,backendSecret);
  if(Object.keys(overrides).length||!ms(serverNowMs))
    fail("client_override_or_clock");
  const week=windowFor(firstOpenMs,weekIndex);
  if(serverNowMs<week.openedAtMs)
    fail("league_not_open");
  const isFrozen=serverNowMs>=week.closeAtMs;
  const all=await db.collection(LEAGUE_ROOT)
    .where("weekId","==",week.weekId).get();
  if(!Array.isArray(all.docs)||all.docs.length>MAX_EVENT_ROWS)
    fail("too_many_receipts");
  const seen=new Set(),accounts=new Map();
  for(const snap of all.docs){
    const raw=snap.data();
    if(!raw||snap.id!==week.weekId+"_"+raw.eventKey||
       seen.has(raw.eventKey))fail("duplicate_or_forged_receipt_id");
    seen.add(raw.eventKey);
    const ok=await verifyPairedReceipt(db,raw,week,serverNowMs);
    const prev=accounts.get(ok.accountKey)||{accountKey:ok.accountKey,
      weeklyXp:0,verifiedTaskCount:0,reachedAtMs:0};
    prev.weeklyXp+=20;
    prev.verifiedTaskCount+=1;
    prev.reachedAtMs=Math.max(prev.reachedAtMs,ok.sourceCreatedAtMs);
    if(!ms(prev.weeklyXp)||!ms(prev.verifiedTaskCount))
      fail("overflow");
    accounts.set(ok.accountKey,prev);
  }
  const sorted=[...accounts.values()].sort((a,b)=>
    b.weeklyXp-a.weeklyXp||
    b.verifiedTaskCount-a.verifiedTaskCount||
    a.reachedAtMs-b.reachedAtMs||
    a.accountKey.localeCompare(b.accountKey,"en"));
  const topTen=[];
  for(const [i,row] of sorted.slice(0,10).entries()){
    const profileSnap=await db.doc(profilePath(row.accountKey,backendSecret)).get();
    if(!profileSnap.exists)fail("missing_private_public_profile");
    const p=profileSnap.data();
    if(p.issuer!=="stage44_private_profile_fixture_only"||
       p.emulatorOnly!==true||
       p.accountKey!==row.accountKey||
       !text(p.displayName,NAME)||
       !text(p.activePublicId,PUBLIC_ID)||
       !Number.isSafeInteger(p.level)||p.level<1||
       p.level>99999)
      fail("unsafe_profile_fixture");
    topTen.push(Object.freeze({
      place:i+1,participantId:qaId(row.accountKey,backendSecret),
      displayName:p.displayName,activePublicId:p.activePublicId,
      level:p.level,weeklyXp:row.weeklyXp,
      verifiedTaskCount:row.verifiedTaskCount,
      plannedDiamonds:PRIZES[i],reachedAtMs:row.reachedAtMs,
    }));
  }
  const snapshot={source:SOURCE,emulatorOnly:true,
    weekId:week.weekId,sealedAtMs:isFrozen?week.closeAtMs:null,
    rows:topTen.map(r=>({
      place:r.place,participantId:r.participantId,weeklyXp:r.weeklyXp,
      verifiedTaskCount:r.verifiedTaskCount,reachedAtMs:r.reachedAtMs
    }))};
  if(isFrozen)previewFrozenResult({firstOpenMs,weekIndex,
    serverNowMs,snapshot});
  return Object.freeze({
    weekId:week.weekId,state:isFrozen?"frozen":"active",
    displayedUntilMs:week.nextOpenMs,
    closeAtMs:week.closeAtMs,
    archiveMonthId:monthOfFinalEligibleInstant(week.closeAtMs),
    projectedAtMs:serverNowMs,
    topTen:Object.freeze(topTen),
    allCompetitorCount:sorted.length,
    plannedTotalDiamonds:topTen.reduce((s,r)=>s+r.plannedDiamonds,0),
    snapshot:isFrozen?Object.freeze(snapshot):null,
    previewOnly:true,emulatorOnly:true,
    actuallyCreditedDiamonds:0,productionReady:false,
    coherentSnapshotGuarantee:false,
  });
}
function previewPrivateMonthlyHistory({monthId,closedWeekPreviews,serverNowMs}){
  if(!/^20\d{2}-(0[1-9]|1[0-2])$/.test(monthId||"")||
     !Array.isArray(closedWeekPreviews)||closedWeekPreviews.length>6||
     !ms(serverNowMs))fail("invalid_monthly_history_request");
  const seen=new Set(),records=[];
  for(const view of closedWeekPreviews){
    if(!view||view.emulatorOnly!==true||view.previewOnly!==true||
       view.state!=="frozen"||!view.snapshot||
       view.archiveMonthId!==monthId||
       view.projectedAtMs>serverNowMs||
       view.closeAtMs>serverNowMs||
       seen.has(view.weekId))fail("invalid_closed_snapshot");
    seen.add(view.weekId);
    records.push(Object.freeze({
      weekId:view.weekId,closedAtMs:view.closeAtMs,
      firstThree:view.topTen.slice(0,3).map(x=>({
        place:x.place,participantId:x.participantId,
        displayName:x.displayName,weeklyXp:x.weeklyXp
      })),
      topTen:view.topTen.map(x=>({
        place:x.place,participantId:x.participantId,
        displayName:x.displayName,weeklyXp:x.weeklyXp
      }))
    }));
  }
  records.sort((a,b)=>a.closedAtMs-b.closedAtMs);
  return Object.freeze({monthId,records:Object.freeze(records),
    readOnly:true,emulatorOnly:true,actuallyCreditedDiamonds:0,
    managerAuthorizationVerified:false,productionReady:false});
}
module.exports=Object.freeze({PROJECT,VERIFIED_ROOT,LEAGUE_ROOT,profilePath,
  qaId,monthOfFinalEligibleInstant,
  previewPrivateTopTenFromAppliedXp,previewPrivateMonthlyHistory});
