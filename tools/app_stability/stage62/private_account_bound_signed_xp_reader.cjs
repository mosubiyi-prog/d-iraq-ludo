"use strict";
/**
 * Stage62: backend-only emulator PRIVATE account-bound weekly XP preview.
 * Joins server-applied ORIGINAL progress receipts (Stage44) with independently
 * reviewed signed task claims (Stage46), then authenticated emulator UID binding.
 *
 * Real original PIN ownership, App Check, legitimate old APK cutover and
 * independently reviewed legacy XP are NOT proved by synthetic fixtures.
 * Therefore NEVER serve as verified production standings; NEVER pay diamonds.
 */
const crypto=require("node:crypto");
const {PROJECT,LEAGUE_ROOT,previewPrivateTopTenFromAppliedXp}=
  require("../../../functions/deda_weekly_stage44_verified_ledger_top10_archive_NOT_EXPORTED.js");
const {validateSignedTaskClaimInTransaction}=
  require("../../../functions/deda_weekly_stage46_private_signed_task_claim_NOT_EXPORTED.js");
const {windowFor}=require(
  "../../functions/deda_weekly_stage31_frozen_league_winner_card_NOT_EXPORTED.js");
const {ROOT:SOURCE_ROOT}=require(
  "../../functions/deda_weekly_stage42_server_share_action_producer_NOT_EXPORTED.js");
const {ROOT:EPOCH_ROOT}=require(
  "../../functions/deda_weekly_stage43_reviewed_cutover_epoch_NOT_EXPORTED.js");
const BINDING_ROOT="deda_weekly_stage62_private_qa_auth_account_bindings";
const ISSUER="stage62_admin_only_authenticated_emulator_uid_binding";
const ACCOUNT=/^[0-9]{10,16}$/,UID=/^[A-Za-z0-9_-]{8,128}$/;
const HEX=/^[0-9a-f]{64}$/;
const block=(what)=>{throw Error("DEDA_STAGE62_REFUSE_"+what);};
function guard({db,authUid,backendSecret}){
 if(process.env.GCLOUD_PROJECT!==PROJECT||
    process.env.FIRESTORE_EMULATOR_HOST!=="127.0.0.1:8080"||
    process.env.DEDA_STAGE62_EMULATOR_ONLY!=="true"||
    !process.env.FIREBASE_AUTH_EMULATOR_HOST||
    !process.env.FIREBASE_FUNCTIONS_EMULATOR_HOST||
    !db||typeof db.doc!=="function"||
    !Buffer.isBuffer(backendSecret)||backendSecret.length<32||
    !UID.test(authUid||""))block("EMULATOR_AUTH_REQUIRED");
}
const value=s=>s.exists?s.data():null;
const digest=(key,s)=>crypto.createHmac("sha256",key).update(s).digest("hex");
function verifiedBind(doc,authUid,backendSecret){
 if(!doc||Object.keys(doc).length!==8||
    doc.issuer!==ISSUER||doc.emulatorOnly!==true||
    doc.canAuthorizeProduction!==false||doc.canCreditDiamonds!==false||
    doc.authUid!==authUid||!ACCOUNT.test(doc.accountKey||"")||
    !HEX.test(doc.accountDigest||"")||
    doc.accountDigest!==digest(backendSecret,"account:"+doc.accountKey))
    block("UID_NOT_BOUND_BY_SERVER");
 return doc.accountKey;
}
async function verifyEverySignedOriginalTask({db,firstOpenMs,weekIndex,
  serverNowMs,backendSecret}){
 const week=windowFor(firstOpenMs,weekIndex);
 const records=await db.collection(LEAGUE_ROOT)
   .where("weekId","==",week.weekId).get();
 if(records.size>5000)block("TOO_MANY_EVENTS");
 const seen=new Set();
 for(const record of records.docs){
   const row=record.data();
   if(!row||row.emulatorOnly!==true||row.weekId!==week.weekId||
      !HEX.test(row.eventKey||"")||
      record.id!==week.weekId+"_"+row.eventKey||
      seen.has(row.eventKey)||
      !ACCOUNT.test(row.accountKey||"")||
      !Number.isSafeInteger(row.createdAtMs)||
      row.createdAtMs<week.openedAtMs||row.createdAtMs>=week.closeAtMs)
     block("UNTRUSTED_WEEKLY_EVENT");
   seen.add(row.eventKey);
   const read=async p=>value(await db.doc(p).get());
   const [source,migration,epoch]=await Promise.all([
     read(SOURCE_ROOT+"/"+row.eventKey),
     read("deda_progress_migrations/"+row.accountKey),
     read(EPOCH_ROOT+"/"+row.accountKey)
   ]);
   if(!source||!migration||!epoch||
      source.eventKey!==row.eventKey||
      source.accountKey!==row.accountKey||
      source.dayId!==row.dayId||
      source.originalLocalClaimAwarded!=="UNKNOWN_REQUIRES_MIGRATION_REVIEW"||
      epoch.emulatorOnly!==true||epoch.canAuthorizeProduction!==false)
      block("ORIGINAL_SOURCE_OR_CUTOVER_MISSING");
   // Existing Stage46 validator re-reads independent source, migration,
   // epoch and privileged reviewer, then checks the receipt HMAC. If any
   // record is client-forged or unreviewed, reject the WHOLE leaderboard.
   try{
     await validateSignedTaskClaimInTransaction({
       reader:{get:read},accountKey:row.accountKey,dayId:row.dayId,
       eventKey:row.eventKey,originalShareId:source.originalShareId,
       sourceCreatedAtMs:source.sourceCreatedAtMs,
       serverNowMs, migrationId:migration.migrationId,backendSecret
     });
   }catch(e){block("SIGNED_ORIGINAL_TASK_REVIEW_MISSING");}
 }
}
async function previewForAuthedViewer({
 db,authUid,backendSecret,firstOpenMs,weekIndex,serverNowMs,
 ...extra
}){
 guard({db,authUid,backendSecret});
 if(Object.keys(extra).length||
    !Number.isSafeInteger(firstOpenMs)||
    !Number.isSafeInteger(weekIndex)||
    !Number.isSafeInteger(serverNowMs))
   block("CLIENT_OVERRIDE_OR_SERVER_CLOCK");
 const binding=await db.doc(BINDING_ROOT+"/"+authUid).get();
 const account=verifiedBind(value(binding),authUid,backendSecret);
 await verifyEverySignedOriginalTask({
   db,firstOpenMs,weekIndex,serverNowMs,backendSecret
 });
 const projected=await previewPrivateTopTenFromAppliedXp({
   db,firstOpenMs,weekIndex,serverNowMs,backendSecret
 });
 // NO actual account phone, private UID, original wallets or raw document
 // fields go to client. Only display-safe synthetic QA profiles.
 const rows=projected.topTen.map(({place,participantId,displayName,
   activePublicId,level,weeklyXp,verifiedTaskCount,plannedDiamonds})=>
   ({place,participantId,displayName,activePublicId,level,
    weeklyXp,verifiedTaskCount,plannedDiamonds}));
 const viewerTag=require(
   "../../functions/deda_weekly_stage44_verified_ledger_top10_archive_NOT_EXPORTED.js"
 ).qaId(account,backendSecret);
 return Object.freeze({
   schema:1,source:"stage62_PRIVATE_SIGNED_XP_PREVIEW_NOT_VERIFIED_LEAGUE",
   emulatorOnly:true,readOnly:true,verified:false,
   productionReady:false,productionAppCheckVerified:false,
   originalAuthOwnershipVerified:false,oldApkWriterFenced:false,
   accountAssetsMigrated:false,canCreditDiamonds:false,
   canIssueGift:false,canWriteLevelXp:false,canWriteWallet:false,
   originalQuizChanged:false,
   weekId:projected.weekId,
   phase:projected.state,viewerParticipantId:viewerTag,
   viewerPlace:rows.find(x=>x.participantId===viewerTag)?.place??null,
   weekXP:rows.find(x=>x.participantId===viewerTag)?.weeklyXp??0,
   topTen:rows,
   actuallyCreditedDiamonds:0
 });
}
module.exports={PROJECT,BINDING_ROOT,ISSUER,verifiedBind,previewForAuthedViewer};
