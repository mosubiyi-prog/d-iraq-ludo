"use strict";
/**
 * Stage37: READ-ONLY connection from ORIGINAL location-share provenance to
 * EXISTING, undeployed verified-progress archive migration gate.
 *
 * This is NOT a trusted task-completion writer, approved old-client writer
 * fence or Firebase Cloud Function. It only checks both preconditions and
 * derives the account/day/task receipt contract without writing a cent/XP.
 * Nothing in this module can approve a migration, create a task claim, rank
 * a player, or settle gifts.
 */
const core=require("../tools/app_stability/progress_archive/reconcile-core.cjs");
const {loadMigratedContext}=require(
  "../tools/app_stability/progress_archive/migration-gate.cjs");
const {PROJECT,dayInIraq}=require(
  "./deda_weekly_xp_atomic_shadow_issuer_NOT_EXPORTED.js");
const {clockState}=require(
  "./deda_weekly_stage31_frozen_league_winner_card_NOT_EXPORTED.js");
const {auditOriginalShareRecipientProvenance}=require(
  "./deda_weekly_stage36_original_source_provenance_NOT_EXPORTED.js");

const SHARE=/^[A-Za-z0-9]{20}$/;
const ACCOUNT=/^[0-9]{10,16}$/;
const UID=/^[A-Za-z0-9_-]{1,128}$/;
const TASK="share_personal_location";
function fail(s){throw Error("DEDA_STAGE37_MIGRATION_GATE_BLOCK_"+s);}
function ms(v){const x=v?.toMillis?.();if(!Number.isSafeInteger(x)||x<0)fail("timestamp");return x;}
function record(s,label){
  if(!s?.exists||typeof s.data!=="function")fail("missing_"+label);
  const v=s.data();
  if(!v||typeof v!=="object"||Array.isArray(v))fail("invalid_"+label);
  return v;
}
function emulator(db){
  if(process.env.GCLOUD_PROJECT!==PROJECT||
    !process.env.FIRESTORE_EMULATOR_HOST||
    !db||typeof db.runTransaction!=="function"||typeof db.doc!=="function")
    fail("private_emulator_only");
}
/**
 * For active league hours. A later, separately reviewed original-source
 * verifier must cover 00:00-06:00 as lifetime-level XP ONLY without league XP.
 * This guard deliberately fails closed for frozen shares, rather than
 * fabricating a task proof or losing/changing existing local user XP.
 */
async function previewReviewedTaskCutover({
  db,shareId,firstOpenMs,serverNowMs
}){
  emulator(db);
  if(!SHARE.test(shareId||"")||
     !Number.isSafeInteger(serverNowMs)||serverNowMs<0)
    fail("invalid_input");
  const calendar=clockState({firstOpenMs,serverNowMs});
  if(calendar.phase!=="active"||!calendar.current)
    fail("frozen_source_requires_separate_level_only_verifier");
  // Checks real-shaped ORIGINAL sender AND independent recipient canonical ID.
  // Rejects untrusted source before even reading any hypothetical migration.
  const proof=await auditOriginalShareRecipientProvenance({
    db,shareId,firstOpenMs,serverNowMs});
  if(proof.privateEmulatorSourceAuditOnly!==true||
     proof.originalSourceId!==shareId||
     proof.distinctRecipientCanonicalAccount!==true||
     proof.sourceOwnershipValidated!==true||
     proof.serverVerifiedOriginalTaskClaim!==false||
     proof.serverReconciledOriginalLevelXp!==false)
    fail("untrusted_original_source");

  // Single read-only Firestore transaction: archived progress, reviewer
  // evidence, old-writer settlement and original owner/source re-read.
  return db.runTransaction(async tx=>{
    const source=record(await tx.get(db.doc(
      "deda_location_shares/"+shareId)),"original_share");
    const uid=source.senderUid;
    if(!UID.test(uid||"")||source.shareType!=="current"||
       source.status!=="pending"||source.senderPublicId===
       source.recipientPublicId||source.placeId!==""||
       source.placeName!==""||ms(source.createdAt)>serverNowMs||
       ms(source.createdAt)!==ms(source.updatedAt)||
       ms(source.createdAt)<calendar.current.openedAtMs||
       ms(source.createdAt)>=calendar.current.closeAtMs)
      fail("original_source_changed");
    const user=record(await tx.get(db.doc("users/"+uid)),"owner");
    if(!ACCOUNT.test(user.accountKey||"")||
       user.uid!=null&&user.uid!==uid||
       user.sharePersonalId!==source.senderPublicId)
      fail("canonical_account_mismatch");

    const session=record(await tx.get(db.doc("deda_sessions/"+uid)),
      "owner_session");
    const profile=record(await tx.get(db.doc(
      "deda_account_profiles/"+user.accountKey)),
      "account_profile");
    if(session.accountKey!==user.accountKey||session.uid!==uid||
       !Array.isArray(profile.trustedInstallIds)||
       !profile.trustedInstallIds.includes(session.installId)||
       profile.accountKey!==user.accountKey)
      fail("owner_install_changed");
    const senderId=record(await tx.get(db.doc("deda_share_ids/"+source.senderPublicId)),"sender_id");
    if(senderId.ownerUid!==uid||senderId.kind!=="personal"||senderId.active!==true)
      fail("invalid_sender_id");
    const receiverId=record(await tx.get(db.doc(
      "deda_share_ids/"+source.recipientPublicId)),"recipient_id");
    if(!UID.test(receiverId.ownerUid||"")||
       receiverId.ownerUid===uid||receiverId.active!==true||
       receiverId.kind!=="personal")
      fail("invalid_recipient");
    const recipient=record(await tx.get(db.doc(
      "users/"+receiverId.ownerUid)),"recipient_user");
    if(!ACCOUNT.test(recipient.accountKey||"")||
       recipient.accountKey===user.accountKey||
       recipient.sharePersonalId!==source.recipientPublicId)
      fail("same_canonical_recipient");

    const accountKey=user.accountKey;
    // This is the ORIGINAL future approved reviewed migration, never a new
    // zero-balance wallet or migration flag supplied by the app.
    const reader={
      get:async path=>{
        const snap=await tx.get(db.doc(path));
        return snap.exists?snap.data():null;
      }
    };
    const {migration,state}=await loadMigratedContext(reader,accountKey);
    // Migration settlement has old-client writer fence ID. This does not
    // prove old published APKs actually stopped writing; must be separately
    // reviewed before any live grant. The preflight remains read-only.
    if(migration.phase!=="cutover-complete"||
       !ACCOUNT.test(state.accountKey)||
       state.accountKey!==accountKey)fail("migration_not_verified");
    const dayId=dayInIraq(ms(source.createdAt));
    const normalized=core.parseReceipt({
      format:1,accountKey,source:"task-claim-v1",
      sourceId:"daily-task|"+dayId+"|"+TASK,kind:"award",
      delta:{points:5,coins:0,xp:20,earnedDiamonds:0}
    },accountKey);
    const eventKey=core.eventKey(normalized);
    // Review must classify historical task claims before considering
    // the receipt. A cutover flag alone cannot classify a fresh mobile share.
    const classification=await reader.get(
      "deda_progress_migrations/"+accountKey+"/classifications/"+eventKey);
    if(!classification)fail("migration_classification_required");
    if(classification.format!==1||
       classification.accountKey!==accountKey||
       classification.migrationId!==migration.migrationId||
       classification.evidenceDigest!==migration.evidenceDigest||
       !["included-in-baseline","after-cutover"].includes(
         classification.disposition)||
       !classification.receipt||
       !core.sameEvent(
         core.parseReceipt(classification.receipt,accountKey),normalized))
      fail("migration_classification_conflict");
    const historicallyIncluded=
      classification.disposition==="included-in-baseline";
    const applied=await reader.get(
      "deda_verified_progress/"+accountKey+"/events/"+eventKey);
    if(historicallyIncluded&&applied!==null)
      fail("historical_classification_replayed");
    // A historical or already-applied task cannot be awarded a second time;
    // ownership of another phone, client UI or alias changes nothing.
    if(applied!==null){
      if(applied.eventKey!==eventKey||
         !Number.isSafeInteger(applied.appliedVersion)||
         applied.appliedVersion<1||applied.appliedVersion>state.version||
         !applied.receipt||
         !core.sameEvent(core.parseReceipt(applied.receipt,accountKey),
          normalized))fail("conflicting_applied_event");
    }
    return Object.freeze({
      previewOnly:true,existingProgressPath:"deda_verified_progress",
      source:"original_share_and_reviewed_migration_read_only",
      originalTaskId:TASK,dayId,weekId:calendar.current.weekId,
      originalReceiptSource:"task-claim-v1",eventKey,
      alreadyApplied:applied!==null,
      includedInReviewedLegacyBaseline:historicallyIncluded,
      originalBalancePreserved:true,
      futureNewTaskPoints:(applied!==null||historicallyIncluded)?0:5,
      futureNewLifetimeXp:(applied!==null||historicallyIncluded)?0:20,
      futureLeagueXp:(applied!==null||historicallyIncluded)?0:20,
      actualTaskPointsAdded:0,actualLifetimeXpAdded:0,
      actualLeagueXpAdded:0,actualDiamondsAdded:0,
      canWriteProgress:false,canPublishLeague:false,
      canIssueTaskReceipt:false,canGrantDiamonds:false,
      pendingGuards:Object.freeze([
        "original_server_task_claim_producer",
        "live_legacy_writer_fence_attestation",
        "production_firestore_rules_self_share_fix",
        "real_AppCheck_and_signed_multi_device_QA"
      ])
    });
  });
}
module.exports=Object.freeze({previewReviewedTaskCutover});
