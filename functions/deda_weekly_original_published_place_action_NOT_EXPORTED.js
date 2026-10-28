"use strict";
/**
 * PRIVATE Firestore emulator proof for a REAL ORIGINAL DEDA action:
 * sending one's approved, published PLACE to a distinct canonical account.
 *
 * This observes the same deda_location_shares records written by
 * DedaBackend.createLocationShare(shareType:'place'). It proves only that
 * the cross-account place-share ACTION occurred, NOT that the old APK did
 * (or did not) already credit local points/level XP/coins.
 *
 * Do not export to functions/index.js, deploy, or treat this as a payout.
 */
const core=require("../tools/app_stability/progress_archive/reconcile-core.cjs");
const {PROJECT,dayInIraq}=require(
  "./deda_weekly_xp_atomic_shadow_issuer_NOT_EXPORTED.js");
const {clockState}=require(
  "./deda_weekly_stage31_frozen_league_winner_card_NOT_EXPORTED.js");

const TASK="share_registered_place";
const ISSUER="private_original_published_place_share_action_v1_emulator_only";
const ROOT="deda_weekly_private_published_place_share_action_proofs";
const UID=/^[A-Za-z0-9_-]{1,128}$/;
const ACCOUNT=/^[0-9]{10,16}$/;
const ID=/^@DEDA-[A-Z0-9]{6}$/;
const SHARE=/^[A-Za-z0-9]{20}$/;
const PLACE=/^[A-Za-z0-9_-]{1,128}$/;
function fail(code){throw Error("DEDA_ORIGINAL_PLACE_ACTION_"+code);}
function okayMs(n){return Number.isSafeInteger(n)&&n>=0;}
function at(x){const n=x?.toMillis?.();if(!okayMs(n))fail("server_timestamp");return n;}
function data(doc,label){
  if(!doc?.exists||typeof doc.data!=="function")fail("missing_"+label);
  const value=doc.data();
  if(!value||typeof value!=="object"||Array.isArray(value))fail("shape_"+label);
  return value;
}
function local(db){
  if(process.env.GCLOUD_PROJECT!==PROJECT||
      !process.env.FIRESTORE_EMULATOR_HOST||
      typeof db?.doc!=="function"||
      typeof db?.runTransaction!=="function")
    fail("emulator_only");
}
function receiptFor(accountKey,dayId){
  const receipt=core.parseReceipt({
    format:1,accountKey,source:"task-claim-v1",
    sourceId:"daily-task|"+dayId+"|"+TASK,kind:"award",
    delta:{points:5,coins:10,xp:20,earnedDiamonds:0}
  },accountKey);
  return Object.freeze({receipt,eventKey:core.eventKey(receipt)});
}
async function verifyOriginalPublishedPlaceShareAction({
  db,shareId,firstOpenMs,serverNowMs
}){
  local(db);
  if(!SHARE.test(shareId||"")||!okayMs(serverNowMs))
    fail("untrusted_backend_input");
  const clock=clockState({firstOpenMs,serverNowMs});
  if(!clock.current||!["active","frozen"].includes(clock.phase))
    fail("league_not_started");
  return db.runTransaction(async tx=>{
    const share=data(await tx.get(db.doc("deda_location_shares/"+shareId)),
      "original_share");
    const from=share.senderPublicId,to=share.recipientPublicId;
    if(!UID.test(share.senderUid||"")||
       !ID.test(from||"")||!ID.test(to||"")||from===to||
       share.shareType!=="place"||share.status!=="pending"||
       !PLACE.test(share.placeId||"")||
       typeof share.placeName!=="string"||
       share.placeName.length<2||share.placeName.length>150||
       share.senderName!==share.placeName||
       ![15,30,60].includes(share.durationMinutes)||
       !Number.isFinite(share.latitude)||share.latitude< -90||share.latitude>90||
       !Number.isFinite(share.longitude)||share.longitude< -180||share.longitude>180)
      fail("original_place_share_shape");
    const created=at(share.createdAt),updated=at(share.updatedAt),
      expires=at(share.expiresAt);
    if(created!==updated||created>serverNowMs||
       serverNowMs-created>300000||
       created<clock.current.openedAtMs||
       created>=clock.current.nextOpenMs||
       expires<=created||expires>created+61*60000||
       dayInIraq(created)!==dayInIraq(serverNowMs))
      fail("place_share_baghdad_window");
    const [senderSnap,senderIdSnap,recipientIdSnap,sessionSnap,publishedSnap]=
      await Promise.all([
        tx.get(db.doc("users/"+share.senderUid)),
        tx.get(db.doc("deda_share_ids/"+from)),
        tx.get(db.doc("deda_share_ids/"+to)),
        tx.get(db.doc("deda_sessions/"+share.senderUid)),
        tx.get(db.doc("published_places/"+share.placeId)),
      ]);
    const sender=data(senderSnap,"original_sender"),
      senderId=data(senderIdSnap,"original_place_id"),
      recipientId=data(recipientIdSnap,"recipient_personal_id"),
      session=data(sessionSnap,"original_session"),
      published=data(publishedSnap,"published_place");
    const account=sender.accountKey;
    if(!ACCOUNT.test(account||"")||
       sender.uid!=null&&sender.uid!==share.senderUid||
       sender.sharePlaceId!==from||
       senderId.kind!=="place"||senderId.active!==true||
       senderId.ownerUid!==share.senderUid||
       senderId.publicId!=null&&senderId.publicId!==from||
       recipientId.kind!=="personal"||recipientId.active!==true||
       !UID.test(recipientId.ownerUid||"")||
       recipientId.ownerUid===share.senderUid||
       recipientId.publicId!=null&&recipientId.publicId!==to||
       session.uid!==share.senderUid||session.accountKey!==account||
       !UID.test(session.installId||"")||
       published.published!==true||
       published.accountKey!==account||
       published.placeName!==share.placeName||
       published.latitude!==share.latitude||
       published.longitude!==share.longitude)
      fail("published_place_or_sender_identity");
    const [recipientSnap,profileSnap]=await Promise.all([
      tx.get(db.doc("users/"+recipientId.ownerUid)),
      tx.get(db.doc("deda_account_profiles/"+account)),
    ]);
    const recipient=data(recipientSnap,"recipient_owner"),
      profile=data(profileSnap,"original_account_profile");
    if(!ACCOUNT.test(recipient.accountKey||"")||
       recipient.accountKey===account||
       recipient.uid!=null&&recipient.uid!==recipientId.ownerUid||
       recipient.sharePersonalId!==to||
       profile.accountKey!==account||
       !Array.isArray(profile.trustedInstallIds)||
       !profile.trustedInstallIds.includes(session.installId))
      fail("cross_account_or_trusted_install");
    const dayId=dayInIraq(created);
    const {eventKey}=receiptFor(account,dayId);
    const previous=await tx.get(db.doc(ROOT+"/"+eventKey));
    if(previous.exists){
      const old=data(previous,"existing_action");
      if(old.issuer!==ISSUER||old.emulatorOnly!==true||
         old.canAuthorizeProduction!==false||
         old.accountKey!==account||old.taskId!==TASK||
         old.dayId!==dayId||old.eventKey!==eventKey||
         !SHARE.test(old.originalShareId||"")||
         old.originalLocalClaimAwarded!=="UNKNOWN_REQUIRES_MIGRATION_REVIEW"||
         old.xpGranted!==0||old.pointsGranted!==0||
         old.coinsGranted!==0||old.diamondsGranted!==0)
        fail("conflicting_existing_action");
      return Object.freeze({outcome:"already_verified",eventKey,
        levelXpAdded:0,leagueXpAdded:0,pointsAdded:0,coinsAdded:0,
        diamondsAdded:0,emulatorOnly:true});
    }
    tx.create(db.doc(ROOT+"/"+eventKey),{
      issuer:ISSUER,emulatorOnly:true,canAuthorizeProduction:false,
      serverVerifiedAction:true,
      accountKey:account,taskId:TASK,dayId,eventKey,
      originalShareId:shareId,publishedPlaceId:share.placeId,
      originalSenderUid:share.senderUid,
      sourceCreatedAtMs:created,sourceVerifiedAtMs:serverNowMs,
      originalLocalClaimAwarded:"UNKNOWN_REQUIRES_MIGRATION_REVIEW",
      verifiedAs:"published_owned_place_cross_account_share_only",
      xpGranted:0,pointsGranted:0,coinsGranted:0,diamondsGranted:0,
    });
    return Object.freeze({outcome:"place_action_verified",eventKey,dayId,
      levelXpAdded:0,leagueXpAdded:0,pointsAdded:0,coinsAdded:0,
      diamondsAdded:0,emulatorOnly:true});
  });
}
module.exports=Object.freeze({PROJECT,TASK,ROOT,ISSUER,receiptFor,
  verifyOriginalPublishedPlaceShareAction});
