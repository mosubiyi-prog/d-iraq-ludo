"use strict";
/**
 * Stage42 backend-owned proof that an ORIGINAL location-share ACTION happened.
 *
 * LOCAL REAL FIRESTORE EMULATOR ONLY. Intentionally NOT exported from
 * functions/index.js. A valid client-authored share plus strict server-side
 * cross-account validation proves the share ACTION, NOT that the original
 * phone-local +5 points, +20 XP, +10 social coins were/weren't already added.
 * Only an independently reviewed migration classification plus an actually
 * enforced old-client cutover can make any later grant safe. The Stage42 award
 * adapter REQUIRES these additional gates (simulated cutover still a fixture).
 *
 * Do not deploy, call against live Firebase, use as a Play/SSV receipt, or
 * grant any diamonds. ServerNow/ShareId are trusted backend inputs, not a
 * public callable accepting client identities or user-supplied amounts.
 */
const core=require("../tools/app_stability/progress_archive/reconcile-core.cjs");
const {PROJECT,dayInIraq}=require(
  "./deda_weekly_xp_atomic_shadow_issuer_NOT_EXPORTED.js");
const {clockState}=require(
  "./deda_weekly_stage31_frozen_league_winner_card_NOT_EXPORTED.js");
const TASK="share_personal_location";
const ISSUER="stage42_server_verified_original_share_ACTION_emulator_only";
const ROOT="deda_weekly_stage42_server_verified_share_actions_private";
const UID=/^[A-Za-z0-9_-]{1,128}$/;
const ACCOUNT=/^[0-9]{10,16}$/;
const PERSONAL=/^@DEDA-[A-Z0-9]{6}$/;
const SHARE=/^[A-Za-z0-9]{20}$/;
function abort(code){throw Error("DEDA_STAGE42_SERVER_ACTION_BLOCK_"+code);}
function validMs(x){return Number.isSafeInteger(x)&&x>=0;}
function millis(x){const v=x?.toMillis?.();if(!validMs(v))abort("invalid_server_timestamp");return v;}
function doc(s,label){
  if(!s?.exists||typeof s.data!=="function")abort("missing_"+label);
  const d=s.data();
  if(!d||typeof d!=="object"||Array.isArray(d))abort("invalid_"+label);
  return d;
}
function requireLocal(db){
  if(process.env.GCLOUD_PROJECT!==PROJECT||
     !process.env.FIRESTORE_EMULATOR_HOST||
     !db||typeof db.doc!=="function"||
     typeof db.runTransaction!=="function")
    abort("private_emulator_only");
}
function receiptFor(account,day){
  const receipt=core.parseReceipt({
    format:1,accountKey:account,source:"task-claim-v1",
    sourceId:"daily-task|"+day+"|"+TASK,kind:"award",
    // ORIGINAL signed wallet grants +10 social coins per claimed task.
    delta:{points:5,coins:10,xp:20,earnedDiamonds:0}
  },account);
  return {receipt,eventKey:core.eventKey(receipt)};
}
/** An Admin-SDK-only onCreate-style adapter (no user-provided score or UID).
 * Record one immutable original share-ACTION proof per account/Baghdad day.
 * It NEVER claims that old local XP/coins have not already been granted.
 */
async function recordVerifiedOriginalShareAction({
  db,shareId,firstOpenMs,serverNowMs
}){
  requireLocal(db);
  if(!SHARE.test(shareId||"")||!validMs(serverNowMs))
    abort("untrusted_backend_event_input");
  const clock=clockState({firstOpenMs,serverNowMs});
  if(!clock.current||!["active","frozen"].includes(clock.phase))
    abort("league_not_started");
  const sourceRef=db.doc("deda_location_shares/"+shareId);
  return db.runTransaction(async tx=>{
    const share=doc(await tx.get(sourceRef),"original_share");
    const from=share.senderPublicId,to=share.recipientPublicId;
    if(!UID.test(share.senderUid||"")||
       !PERSONAL.test(from||"")||!PERSONAL.test(to||"")||
       from===to||share.shareType!=="current"||
       share.status!=="pending"||
       typeof share.senderName!=="string"||!share.senderName.length||
       share.placeId!==""||share.placeName!==""||
       ![15,30,60].includes(share.durationMinutes)||
       !Number.isFinite(share.latitude)||share.latitude < -90||
       share.latitude>90||
       !Number.isFinite(share.longitude)||share.longitude < -180||
       share.longitude>180)
      abort("unverified_original_share_shape");
    const created=millis(share.createdAt),updated=millis(share.updatedAt);
    const expires=millis(share.expiresAt);
    if(created!==updated||created>serverNowMs||
       serverNowMs-created>300000||
       created<clock.current.openedAtMs||
       created>=clock.current.nextOpenMs||
       expires<=created||expires>created+61*60000||
       dayInIraq(created)!==dayInIraq(serverNowMs))
      abort("original_share_outside_current_baghdad_window");
    const [senderUserSnap,senderIdSnap,recipientIdSnap,senderSessionSnap]=
      await Promise.all([
        tx.get(db.doc("users/"+share.senderUid)),
        tx.get(db.doc("deda_share_ids/"+from)),
        tx.get(db.doc("deda_share_ids/"+to)),
        tx.get(db.doc("deda_sessions/"+share.senderUid)),
      ]);
    const sender=doc(senderUserSnap,"sender");
    const senderId=doc(senderIdSnap,"sender_id");
    const receiverId=doc(recipientIdSnap,"recipient_id");
    const session=doc(senderSessionSnap,"sender_session");
    const account=sender.accountKey;
    if(!ACCOUNT.test(account||"")||
       sender.uid!=null&&sender.uid!==share.senderUid||
       sender.sharePersonalId!==from||
       sender.name!==share.senderName||
       senderId.ownerUid!==share.senderUid||
       senderId.kind!=="personal"||senderId.active!==true||
       senderId.publicId!=null&&senderId.publicId!==from||
       !UID.test(receiverId.ownerUid||"")||
       receiverId.ownerUid===share.senderUid||
       receiverId.kind!=="personal"||receiverId.active!==true||
       receiverId.publicId!=null&&receiverId.publicId!==to||
       session.uid!==share.senderUid||
       session.accountKey!==account||
       !UID.test(session.installId||""))
      abort("source_owner_or_session_inconsistent");
    const [receiverSnap,profileSnap]=await Promise.all([
      tx.get(db.doc("users/"+receiverId.ownerUid)),
      tx.get(db.doc("deda_account_profiles/"+account))
    ]);
    const receiver=doc(receiverSnap,"receiver");
    const profile=doc(profileSnap,"account_profile");
    if(!ACCOUNT.test(receiver.accountKey||"")||
       receiver.accountKey===account||
       receiver.uid!=null&&receiver.uid!==receiverId.ownerUid||
       receiver.sharePersonalId!==to||
       profile.accountKey!==account||
       !Array.isArray(profile.trustedInstallIds)||
       !profile.trustedInstallIds.includes(session.installId))
      abort("same_canonical_account_or_untrusted_install");
    const day=dayInIraq(created);
    const {eventKey}=receiptFor(account,day);
    const evidenceRef=db.doc(ROOT+"/"+eventKey);
    const previous=await tx.get(evidenceRef);
    if(previous.exists){
      const old=doc(previous,"stored_proof");
      if(old.issuer!==ISSUER||old.emulatorOnly!==true||
         old.canAuthorizeProduction!==false||
         old.accountKey!==account||old.dayId!==day||
         old.taskId!==TASK||old.eventKey!==eventKey||
         old.originalShareId!==shareId&&
         !SHARE.test(old.originalShareId||""))
        abort("conflicting_previous_action_proof");
      return Object.freeze({outcome:"share_action_already_verified",
        originalShareId:old.originalShareId,eventKey,
        levelXpAdded:0,socialCoinsAdded:0,taskPointsAdded:0,
        leagueXpAdded:0,emulatorOnly:true});
    }
    // Must never include flags that pretend old phone-local credits are absent.
    tx.create(evidenceRef,{
      issuer:ISSUER,emulatorOnly:true,canAuthorizeProduction:false,
      serverVerifiedAction:true,accountKey:account,
      dayId:day,taskId:TASK,eventKey,originalShareId:shareId,
      originalSenderUid:share.senderUid,
      sourceCreatedAtMs:created,sourceVerifiedAtMs:serverNowMs,
      originalLocalClaimAwarded:"UNKNOWN_REQUIRES_MIGRATION_REVIEW",
      verifiedAs:"original_cross_account_share_action_only",
      coinsGranted:0,xpGranted:0,pointsGranted:0,diamondsGranted:0,
    });
    return Object.freeze({outcome:"original_share_action_verified",
      eventKey,dayId:day,
      levelXpAdded:0,socialCoinsAdded:0,taskPointsAdded:0,
      leagueXpAdded:0,emulatorOnly:true});
  });
}
module.exports=Object.freeze({PROJECT,ROOT,ISSUER,TASK,receiptFor,
  recordVerifiedOriginalShareAction});
