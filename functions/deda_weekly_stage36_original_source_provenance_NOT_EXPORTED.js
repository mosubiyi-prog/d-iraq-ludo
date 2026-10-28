"use strict";
/**
 * DEDA stage36 — original-share RECIPIENT OWNERSHIP audit, local emulator only.
 *
 * The original location-share record is client-originated under Firestore
 * Rules. Even a valid cross-account share does not certify the separate
 * local task claim, original +5 points, or original +20 lifetime-level XP.
 * This module CANNOT mint any task, league or wallet receipt. It tightens
 * the trusted-source contract before a future independently approved
 * privileged server producer is allowed to exist.
 *
 * NEVER export from functions/index.js. NEVER call on production Firebase.
 */
const {PROJECT}=require("./deda_weekly_xp_atomic_shadow_issuer_NOT_EXPORTED.js");
const {clockState}=require("./deda_weekly_stage31_frozen_league_winner_card_NOT_EXPORTED.js");
const {inspectOriginalDedaPersonalLocationShare}=require(
  "./deda_weekly_stage30_original_share_evidence_NOT_EXPORTED.js");
const ACCOUNT=/^[0-9]{10,16}$/;
const UID=/^[A-Za-z0-9_-]{1,128}$/;
const PERSONAL=/^@DEDA-[A-Z0-9]{6}$/;
function block(reason){throw Error("DEDA_STAGE36_PROVENANCE_BLOCK_"+reason);}
function validMs(value){return Number.isSafeInteger(value)&&value>=0;}
function record(snapshot,label){
  if(!snapshot?.exists||typeof snapshot.data!=="function")
    block("missing_"+label);
  const data=snapshot.data();
  if(!data||typeof data!=="object"||Array.isArray(data))
    block("invalid_"+label);
  return data;
}
function millis(value){
  const ms=value?.toMillis?.();
  if(!validMs(ms))block("not_server_timestamp");
  return ms;
}
function requirePrivateEmulator(db){
  if(process.env.GCLOUD_PROJECT!==PROJECT||
     !process.env.FIRESTORE_EMULATOR_HOST||
     !db||typeof db.doc!=="function"||
     typeof db.runTransaction!=="function")
    block("private_emulator_required");
}
/**
 * READ-ONLY verified-source audit for share_personal_location.
 * Requires a SERVER-supplied source ID, first-open anchor and server clock.
 * No SDK UID, phone alias, task amount, account or XP from the mobile client.
 *
 * The original Stage30 reader checks source shape and sender account. This
 * additional gate verifies that the recipient public ID resolves to a REAL
 * distinct CANONICAL ACCOUNT, rather than merely a different display ID/UID.
 * All relevant records are re-read within one Firestore read transaction.
 * There are NO writes, even when the audit succeeds.
 */
async function auditOriginalShareRecipientProvenance({
  db,shareId,firstOpenMs,serverNowMs
}){
  requirePrivateEmulator(db);
  if(typeof shareId!=="string"||
     !/^[A-Za-z0-9]{20}$/.test(shareId)||!validMs(serverNowMs))
    block("invalid_server_source");
  const clock=clockState({firstOpenMs,serverNowMs});
  if(clock.phase!=="active"||!clock.current)
    block("not_an_active_league_window");
  const week=clock.current;
  const inspected=await inspectOriginalDedaPersonalLocationShare({
    db,shareId,serverNowMs,weekConfig:{
      weekId:week.weekId,startMs:week.openedAtMs,endMs:week.nextOpenMs
    },
  });
  if(inspected.privateServerCandidateOnly!==true||
     inspected.allowedToPay!==false||
     inspected.originalLevelXpApplied!==false||
     inspected.verifiedTaskXpReceipt!==false||
     inspected.taskId!=="share_personal_location"||
     inspected.serverEventAtMs>=week.closeAtMs)
    block("candidate_not_authoritative");
  return db.runTransaction(async tx=>{
    const share=record(await tx.get(db.doc("deda_location_shares/"+shareId)),
      "original_share");
    const senderUid=share.senderUid,from=share.senderPublicId,
      to=share.recipientPublicId;
    if(!UID.test(senderUid||"")||!PERSONAL.test(from||"")||
       !PERSONAL.test(to||"")||from===to||
       share.shareType!=="current"||share.status!=="pending"||
       share.placeId!==""||share.placeName!==""||
       ![15,30,60].includes(share.durationMinutes)||
       !Number.isFinite(share.latitude)||share.latitude< -90||
       share.latitude>90||!Number.isFinite(share.longitude)||
       share.longitude< -180||share.longitude>180)
      block("untrusted_share_in_transaction");
    const created=millis(share.createdAt),updated=millis(share.updatedAt),
      expires=millis(share.expiresAt);
    if(created!==inspected.serverEventAtMs||
       created!==updated||created<week.openedAtMs||
       created>=week.closeAtMs||created>serverNowMs||
       expires<=created||expires>created+61*60000)
      block("source_changed_or_ineligible_clock");
    const ids=await Promise.all([
      tx.get(db.doc("deda_share_ids/"+from)),
      tx.get(db.doc("deda_share_ids/"+to)),
      tx.get(db.doc("users/"+senderUid)),
      tx.get(db.doc("deda_sessions/"+senderUid)),
    ]);
    const senderId=record(ids[0],"sender_id");
    const recipientId=record(ids[1],"recipient_id");
    const sender=record(ids[2],"sender");
    const session=record(ids[3],"sender_session");
    if(!UID.test(recipientId.ownerUid||"")||
       recipientId.ownerUid===senderUid)
      block("recipient_same_uid_or_missing");
    const recipientUid=recipientId.ownerUid;
    const [recipientSnap,profileSnap]=await Promise.all([
      tx.get(db.doc("users/"+recipientUid)),
      tx.get(db.doc("deda_account_profiles/"+inspected.canonicalAccountKey)),
    ]);
    const recipient=record(recipientSnap,"recipient");
    const profile=record(profileSnap,"sender_account_profile");
    if(!ACCOUNT.test(sender.accountKey||"")||
       !ACCOUNT.test(recipient.accountKey||"")||
       sender.accountKey!==inspected.canonicalAccountKey||
       sender.accountKey===recipient.accountKey||
       sender.uid!=null&&sender.uid!==senderUid||
       recipient.uid!=null&&recipient.uid!==recipientUid||
       sender.sharePersonalId!==from||
       recipient.sharePersonalId!==to||
       senderId.ownerUid!==senderUid||
       senderId.kind!=="personal"||senderId.active!==true||
       senderId.publicId!=null&&senderId.publicId!==from||
       recipientId.kind!=="personal"||recipientId.active!==true||
       recipientId.publicId!=null&&recipientId.publicId!==to||
       session.uid!==senderUid||session.accountKey!==sender.accountKey||
       typeof session.installId!=="string"||session.installId.length===0||
       profile.accountKey!==sender.accountKey||
       !Array.isArray(profile.trustedInstallIds)||
       !profile.trustedInstallIds.includes(session.installId))
      block("recipient_not_a_distinct_verified_account");
    // This is explicitly NOT a trusted server-issued task claim. The app's
    // ordinary +5 points and lifetime +20 XP currently have local writers.
    // No real event/score may derive from a client-authored share alone.
    return Object.freeze({
      privateEmulatorSourceAuditOnly:true,
      originalSourceCollection:"deda_location_shares",
      originalSourceId:shareId,
      sourceOwnershipValidated:true,
      distinctRecipientCanonicalAccount:true,
      serverVerifiedOriginalTaskClaim:false,
      serverReconciledOriginalLevelXp:false,
      migrationCutoverVerified:false,
      originalTaskPointsAdded:0,
      originalLifetimeXpAdded:0,
      leagueXpAdded:0,
      canWriteVerifiedProgress:false,
      canPublishLeague:false,
      canGrantDiamonds:false,
      blockedBy:Object.freeze([
        "independent-real-task-claim-producer-required",
        "approved-legacy-progress-migration-and-old-apk-writer-fence-required",
        "production-rules-fix-and-App-Check-review-required"
      ])
    });
  });
}
module.exports=Object.freeze({auditOriginalShareRecipientProvenance});
