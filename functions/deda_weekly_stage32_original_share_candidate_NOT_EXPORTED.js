"use strict";
/**
 * DEDA Stage32: ORIGINAL application deda_location_shares -> protected
 * candidate receipt in a REAL LOCAL Firestore Emulator only.
 *
 * This deliberately DOES NOT confirm original LEVEL XP, grant weekly XP,
 * export any Cloud Function, create gift receipts, or modify a user wallet.
 * A client-created share proves neither GPS truth nor payment entitlement.
 * A future reviewed backend must join server-authoritative original task XP
 * and an audited LIVE rules/identity policy before league points are awarded.
 */
const {PROJECT,ROOT,dayInIraq}=
  require("./deda_weekly_xp_atomic_shadow_issuer_NOT_EXPORTED.js");
const {opaqueReceiptId}=
  require("./deda_weekly_owner_receipt_gate_NOT_EXPORTED.js");
const {clockState}=
  require("./deda_weekly_stage31_frozen_league_winner_card_NOT_EXPORTED.js");
const {inspectOriginalDedaPersonalLocationShare}=
  require("./deda_weekly_stage30_original_share_evidence_NOT_EXPORTED.js");

const ROOT_CANDIDATE="deda_weekly_stage32_share_candidates_fixture_only";
const ISSUER="stage32_local_emulator_original_share_candidate_only";
const SHARE_ID=/^[A-Za-z0-9]{20}$/;
const ACCOUNT=/^[0-9]{10,16}$/;
function abort(reason){throw Error("DEDA_STAGE32_CANDIDATE_BLOCK_"+reason);}
function integer(x){return Number.isSafeInteger(x)&&x>=0;}
function requireEmulator(db){
  if(process.env.GCLOUD_PROJECT!==PROJECT||
     !process.env.FIRESTORE_EMULATOR_HOST||
     !db||typeof db.doc!=="function"||
     typeof db.runTransaction!=="function")
    abort("emulator_only_no_live_deploy");
}
function fields(snap){
  if(!snap?.exists||typeof snap.data!=="function")abort("missing_source");
  const data=snap.data();
  if(!data||typeof data!=="object"||Array.isArray(data))
    abort("invalid_source");
  return data;
}
function observedMs(v){
  const x=v?.toMillis?.();
  if(!integer(x))abort("missing_server_timestamp");
  return x;
}
/**
 * Server-internal trigger simulation. No raw client-supplied UID, account,
 * XP, week ID, or wallet amount. Only source document ID, a server-issued
 * anchored first-open and the test server clock. A real onCreate trigger
 * must authenticate Firebase origin and independently validate LIVE rules.
 */
async function observeOriginalShareOnce({db,shareId,firstOpenMs,serverNowMs}){
  requireEmulator(db);
  if(!SHARE_ID.test(shareId||"")||!integer(serverNowMs))
    abort("invalid_trigger");
  const clock=clockState({firstOpenMs,serverNowMs});
  if(!clock.leagueScoringAllowed||!clock.current)
    abort("frozen_or_not_started");
  const {current:week}=clock;
  const weekConfig={weekId:week.weekId,startMs:week.openedAtMs,
    endMs:week.nextOpenMs}; // Stage30 reader uses a 7-day week.
  // Stage30 independently checks original persisted shape + original ID,
  // canonical account, linked UID/session, verified installs and timestamps.
  const verified=await inspectOriginalDedaPersonalLocationShare({
    db,shareId,weekConfig,serverNowMs});
  if(verified.privateServerCandidateOnly!==true||
     verified.allowedToPay!==false||
     verified.originalLevelXpApplied!==false||
     verified.verifiedTaskXpReceipt!==false||
     !ACCOUNT.test(verified.canonicalAccountKey||"")||
     verified.taskId!=="share_personal_location"||
     verified.weekId!==week.weekId||
     verified.serverEventAtMs<week.openedAtMs||
     verified.serverEventAtMs>=week.closeAtMs||
     verified.serverEventAtMs>serverNowMs)
    abort("not_an_eligible_pre_midnight_source");
  const account=verified.canonicalAccountKey;
  const dayId=dayInIraq(verified.serverEventAtMs);
  const candidateId=opaqueReceiptId({
    accountKey:account,dayId,taskId:"share_personal_location"
  });
  const ref=db.doc(ROOT_CANDIDATE+"/"+candidateId);
  const shareRef=db.doc("deda_location_shares/"+shareId);

  return db.runTransaction(async tx=>{
    // Re-read original event AND all ownership dependencies inside tx.
    // Prevent source/session changes between precheck and commit.
    const source=fields(await tx.get(shareRef));
    const uid=source.senderUid,from=source.senderPublicId,
      to=source.recipientPublicId;
    if(!/^[A-Za-z0-9_-]{1,128}$/.test(uid||"")||
       !/^@DEDA-[A-Z0-9]{6}$/.test(from||"")||
       !/^@DEDA-[A-Z0-9]{6}$/.test(to||""))
      abort("untrusted_original_sender");
    const refs=[
      db.doc("users/"+uid),db.doc("deda_sessions/"+uid),
      db.doc("deda_account_profiles/"+account),
      db.doc("deda_share_ids/"+from),db.doc("deda_share_ids/"+to),ref
    ];
    const snaps=await Promise.all(refs.map(x=>tx.get(x)));
    const [u,s,profile,sender,recipient]=snaps.slice(0,5).map(fields);
    const old=snaps[5];
    const created=observedMs(source.createdAt);
    if(u.uid!=null&&u.uid!==uid||u.accountKey!==account||
       u.sharePersonalId!==from||
       s.uid!==uid||s.accountKey!==account||
       typeof s.installId!=="string"||s.installId.length===0||
       profile.accountKey!==account||
       !Array.isArray(profile.trustedInstallIds)||
       !profile.trustedInstallIds.includes(s.installId)||
       sender.ownerUid!==uid||sender.kind!=="personal"||
       sender.active!==true||recipient.kind!=="personal"||
       recipient.active!==true||
       source.shareType!=="current"||source.status!=="pending"||
       source.placeId!==""||source.placeName!==""||
       created!==verified.serverEventAtMs||
       observedMs(source.updatedAt)!==created||
       created>=week.closeAtMs||created<week.openedAtMs||
       dayInIraq(created)!==dayId)
      abort("original_share_changed_or_wrong_owner");
    if(old.exists){
      const value=fields(old);
      if(value.issuer!==ISSUER||value.emulatorOnly!==true||
         value.canonicalAccountKey!==account||
         value.dayId!==dayId||value.weekId!==week.weekId||
         value.taskId!=="share_personal_location"||
         value.eventId!==candidateId||value.originalLevelXpApplied!==false||
         value.weeklyXpGranted!==false)
        abort("conflicting_existing_candidate");
      return Object.freeze({outcome:"already_observed_day_task",
        newlyObserved:false,weeklyXpGranted:0,emulatorOnly:true});
    }
    tx.create(ref,{
      issuer:ISSUER,emulatorOnly:true,
      sourceCollection:"deda_location_shares",
      sourceShareId:shareId,
      canonicalAccountKey:account,sourceUid:uid,
      taskId:"share_personal_location",dayId,weekId:week.weekId,
      eventId:candidateId,sourceCreatedAtMs:created,
      observedAtMs:serverNowMs, originalLevelXpApplied:false,
      verifiedOriginalLevelXpReceipt:false,weeklyXpGranted:false,
      candidateOnly:true,payoutEnabled:false,
    });
    return Object.freeze({outcome:"private_candidate_recorded",
      newlyObserved:true,weeklyXpGranted:0,emulatorOnly:true});
  });
}
module.exports=Object.freeze({PROJECT,ROOT,ROOT_CANDIDATE,ISSUER,
  observeOriginalShareOnce});
