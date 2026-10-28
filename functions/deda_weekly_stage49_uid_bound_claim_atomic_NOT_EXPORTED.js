"use strict";
/**
 * Stage46: ATOMIC prototype against EXISTING migrated progress on a dedicated
 * LOCAL Firestore Emulator only. NOT exported by functions/index.js.
 *
 * Client-authored deda_location_shares is NOT proof of earned +5/+20.
 * Server-verified action proof is derived from original share + recipient on the
 * REAL local Firestore Emulator. The old-client writer fence STILL IS a synthetic
 * fixture; migration review and its historic credit classification are synthetic.
 * Stage43 adds an independent per-install account cutover epoch that must
 * START BEFORE source creation, and must match migrated settlement. Records
 * remain explicitly emulator-only and DO NOT revoke old installed APKs.
 * Stage49 additionally requires backend-UID/App signed identity *independent*
 * of mutable mobile session installId and trustedInstallIds (QA fixture).
 * Stage46 additionally requires a separately REVIEWED synthetic original
 * task-claim history and server-HMAC claim receipt. These do not prove live
 * old APK state or real privileged task issuer; NEVER DEPLOY to Firebase.
 * No change to real DEDA rewards, Android APK or existing functions/index.js.
 */
const core=require("../tools/app_stability/progress_archive/reconcile-core.cjs");
const {loadMigratedContext}=require(
  "../tools/app_stability/progress_archive/migration-gate.cjs");
const {PROJECT,dayInIraq}=require(
  "./deda_weekly_xp_atomic_shadow_issuer_NOT_EXPORTED.js");
const {clockState}=require(
  "./deda_weekly_stage31_frozen_league_winner_card_NOT_EXPORTED.js");
const {ROOT:SOURCE_ROOT,ISSUER:SOURCE_ISSUER,receiptFor}=require(
  "./deda_weekly_stage42_server_share_action_producer_NOT_EXPORTED.js");
const {validateReviewedCutoverEpochInTransaction}=require(
  "./deda_weekly_stage43_reviewed_cutover_epoch_NOT_EXPORTED.js");
const {validateSignedTaskClaimInTransaction}=require(
  "./deda_weekly_stage46_private_signed_task_claim_NOT_EXPORTED.js");
const {validateServerUidBindingInTransaction}=require(
  "./deda_weekly_stage49_server_uid_binding_NOT_EXPORTED.js");
const TASK="share_personal_location";
const ISSUER=SOURCE_ISSUER;
const FENCE_ISSUER="stage42_admin_sdk_seeded_old_writer_fence_fixture_only";
const ACTION_ROOT=SOURCE_ROOT;
const FENCE_ROOT="deda_weekly_stage42_private_writer_fences";
const LEAGUE_ROOT="deda_weekly_stage42_private_league_receipts";
const ACCOUNT=/^[0-9]{10,16}$/;
const UID=/^[A-Za-z0-9_-]{1,128}$/;
const ORIGINAL_ID=/^@DEDA-[A-Z0-9]{6}$/;
const SHARE=/^[A-Za-z0-9]{20}$/;
function fail(code){throw Error("DEDA_STAGE43_PRIVATE_BLOCK_"+code);}
function valid(n){return Number.isSafeInteger(n)&&n>=0;}
function timestamp(v){const n=v?.toMillis?.();if(!valid(n))fail("invalid_timestamp");return n;}
function data(s,label){
  if(!s?.exists||typeof s.data!=="function")fail("missing_"+label);
  const d=s.data();
  if(!d||typeof d!=="object"||Array.isArray(d))fail("invalid_"+label);
  return d;
}
function requireEmulator(db){
  if(process.env.GCLOUD_PROJECT!==PROJECT||
     !process.env.FIRESTORE_EMULATOR_HOST||
     !db||typeof db.doc!=="function"||
     typeof db.runTransaction!=="function")
    fail("emulator_only");
}
function requestUid(request){
  const uid=request?.auth?.uid;
  if(!UID.test(uid||"")||request?.auth?.token?.firebase?.sign_in_provider==="anonymous"||
     typeof request?.app?.appId!=="string"||request.app.appId.length<4||
     request.data==null||typeof request.data!=="object"||
     Array.isArray(request.data)||Object.keys(request.data).length!==0)
    fail("auth_appcheck_or_untrusted_client_data");
  return uid;
}
function activeVerifiedSourceAction(f,account,shareId,day,eventKey,now,created){
  // This is evidence that the ORIGINAL share action was server-verified,
  // NOT evidence that a phone-local award has never occurred.
  // Historic credit eligibility is enforced exclusively through migration
  // classification and the separately enforced writer fence (fixture here).
  if(!f||f.issuer!==SOURCE_ISSUER||f.emulatorOnly!==true||
     f.canAuthorizeProduction!==false||
     f.serverVerifiedAction!==true||
     f.accountKey!==account||f.taskId!==TASK||
     f.dayId!==day||f.originalShareId!==shareId||
     f.eventKey!==eventKey||
     f.originalLocalClaimAwarded!=="UNKNOWN_REQUIRES_MIGRATION_REVIEW"||
     f.verifiedAs!=="original_cross_account_share_action_only"||
     f.coinsGranted!==0||f.xpGranted!==0||f.pointsGranted!==0||
     f.diamondsGranted!==0||
     f.sourceCreatedAtMs!==created||
     !valid(f.sourceVerifiedAtMs)||f.sourceVerifiedAtMs<created||
     f.sourceVerifiedAtMs>now||
     now-f.sourceVerifiedAtMs>300000)
    fail("server_verified_original_share_action_required");
}
function activeFenceFixture(f,account,migration){
  if(!f||f.issuer!==FENCE_ISSUER||f.emulatorOnly!==true||
     f.canAuthorizeProduction!==false||f.accountKey!==account||
     f.migrationId!==migration.migrationId||
     f.legacyWritersFencedInFixture!==true||
     f.clientVersionGateReviewedInFixture!==true)
    fail("old_local_writer_fence_not_proven");
}
/**
 * No account, amount, day, week, score or alias is taken from request.data.
 * All ORIGINAL evidence, reviewer migration, fixture task proof, old writer
 * fence, and canonical identity are rechecked inside ONE Firestore transaction.
 * The transaction atomically adds to existing verified-progress state, an
 * immutable account/day/task applied marker, and at most one league receipt.
 * It intentionally cannot run outside the private demo emulator.
 */
async function simulateMigratedTaskAndLeagueAtomic({
  db,request,shareId,firstOpenMs,serverNowMs,backendSecret
}){
  requireEmulator(db);
  const invokingUid=requestUid(request);
  // Private server-only secret must NEVER be accepted from a client payload.
  if(!Buffer.isBuffer(backendSecret)||backendSecret.length<32)
    fail("privileged_claim_signing_secret_required");
  if(!SHARE.test(shareId||"")||!valid(serverNowMs))
    fail("invalid_server_inputs");
  const clock=clockState({firstOpenMs,serverNowMs});
  if(!["active","frozen"].includes(clock.phase)||!clock.current)
    fail("league_not_started");
  // Real Firestore retry policies should be separately reviewed before
  // deployment. This PRIVATE emulator prototype retries only the known
  // transient Firestore emulator "transaction invalid or closed" conflict.
  // The COMPLETE migration/account/proof and applied-event checks rerun
  // inside EACH new transaction. Never retry a domain/security denial.
  const applyOnce=()=>db.runTransaction(async tx=>{
    const share=data(await tx.get(db.doc("deda_location_shares/"+shareId)),
      "original_share");
    const from=share.senderPublicId,to=share.recipientPublicId;
    if(!UID.test(share.senderUid||"")||
       !ORIGINAL_ID.test(from||"")||!ORIGINAL_ID.test(to||"")||
       from===to||share.shareType!=="current"||
       share.status!=="pending"||
       share.placeId!==""||share.placeName!==""||
       ![15,30,60].includes(share.durationMinutes)||
       !Number.isFinite(share.latitude)||share.latitude< -90||
       share.latitude>90||
       !Number.isFinite(share.longitude)||share.longitude< -180||
       share.longitude>180)
      fail("original_source_shape");
    const created=timestamp(share.createdAt);
    const expires=timestamp(share.expiresAt);
    if(created!==timestamp(share.updatedAt)||
       created>serverNowMs||serverNowMs-created>300000||
       created<clock.current.openedAtMs||
       created>=clock.current.nextOpenMs||
       expires<=created||expires>created+61*60000||
       dayInIraq(created)!==dayInIraq(serverNowMs))
      fail("original_share_time");
    const [originSnap,recipientIdSnap,sourceOwnerSnap,sessionSnap,
      currentUserSnap,currentSessionSnap,attestationSnap]=await Promise.all([
      tx.get(db.doc("deda_share_ids/"+from)),
      tx.get(db.doc("deda_share_ids/"+to)),
      tx.get(db.doc("users/"+share.senderUid)),
      tx.get(db.doc("deda_sessions/"+share.senderUid)),
      tx.get(db.doc("users/"+invokingUid)),
      tx.get(db.doc("deda_sessions/"+invokingUid)),
      tx.get(db.doc("deda_weekly_identity_attestations/"+invokingUid)),
    ]);
    const senderId=data(originSnap,"sender_id");
    const receiverId=data(recipientIdSnap,"recipient_id");
    const sourceOwner=data(sourceOwnerSnap,"source_owner");
    const oldSession=data(sessionSnap,"original_sender_session");
    const currentUser=data(currentUserSnap,"invoker_user");
    const currentSession=data(currentSessionSnap,"invoker_session");
    const attestation=data(attestationSnap,"privileged_fixture_identity");
    const account=currentUser.accountKey;
    if(!ACCOUNT.test(account||"")||
       sourceOwner.accountKey!==account||
       sourceOwner.uid!=null&&sourceOwner.uid!==share.senderUid||
       currentUser.uid!=null&&currentUser.uid!==invokingUid||
       sourceOwner.sharePersonalId!==from||
       senderId.ownerUid!==share.senderUid||
       senderId.kind!=="personal"||senderId.active!==true||
       receiverId.kind!=="personal"||receiverId.active!==true||
       !UID.test(receiverId.ownerUid||"")||
       receiverId.ownerUid===share.senderUid||
       oldSession.uid!==share.senderUid||
       oldSession.accountKey!==account||
       currentSession.uid!==invokingUid||
       currentSession.accountKey!==account||
       typeof oldSession.installId!=="string"||
       typeof currentSession.installId!=="string"||
       !UID.test(oldSession.installId)||
       !UID.test(currentSession.installId))
      fail("original_account_or_session_mismatch");
    const [recipientSnap,profileSnap]=await Promise.all([
      tx.get(db.doc("users/"+receiverId.ownerUid)),
      tx.get(db.doc("deda_account_profiles/"+account)),
    ]);
    const recipient=data(recipientSnap,"recipient_owner");
    const profile=data(profileSnap,"canonical_profile");
    if(!ACCOUNT.test(recipient.accountKey||"")||
       recipient.accountKey===account||
       recipient.uid!=null&&recipient.uid!==receiverId.ownerUid||
       recipient.sharePersonalId!==to||
       profile.accountKey!==account||
       !Array.isArray(profile.trustedInstallIds)||
       !profile.trustedInstallIds.includes(oldSession.installId)||
       !profile.trustedInstallIds.includes(currentSession.installId)||
       attestation.issuer!=="privileged_identity_verifier_v1"||
       attestation.state!=="verified"||
       attestation.uid!==invokingUid||
       attestation.accountKey!==account||
       attestation.installId!==currentSession.installId||
       !valid(attestation.issuedAtMs)||!valid(attestation.expiresAtMs)||
       attestation.issuedAtMs>serverNowMs||
       serverNowMs-attestation.issuedAtMs>4*3600000||
       attestation.expiresAtMs<=serverNowMs)
      fail("recipient_or_fresh_attestation");
    const reader={get:async path=>{
      const snap=await tx.get(db.doc(path));
      return snap.exists?snap.data():null;
    }};
    const {migration,state}=await loadMigratedContext(reader,account);
    const dayId=dayInIraq(created);
    const {receipt}=receiptFor(account,dayId);
    const eventKey=core.eventKey(receipt);
    const [classification,proof,fence,existingStateEvent,existingReceipt,
      existingLeague]=await Promise.all([
      reader.get("deda_progress_migrations/"+account+"/classifications/"+eventKey),
      reader.get(ACTION_ROOT+"/"+eventKey),
      reader.get(FENCE_ROOT+"/"+account),
      reader.get("deda_verified_progress/"+account+"/events/"+eventKey),
      reader.get("deda_progress_receipts/"+account+"/events/"+eventKey),
      reader.get(LEAGUE_ROOT+"/"+clock.current.weekId+"_"+eventKey)
    ]);
    if(!classification||Object.keys(classification).length!==6||
       classification.format!==1||
       classification.accountKey!==account||
       classification.migrationId!==migration.migrationId||
       classification.evidenceDigest!==migration.evidenceDigest||
       !["included-in-baseline","after-cutover"].includes(
         classification.disposition)||
       !core.sameEvent(core.parseReceipt(classification.receipt,account),receipt))
      fail("reviewed_task_classification_required");
    // Historical credit must never become a new ranking award.
    if(classification.disposition==="included-in-baseline"){
      if(existingStateEvent!==null||existingReceipt!==null||existingLeague!==null)
        fail("historical_task_conflicting_award");
      return Object.freeze({outcome:"included_in_original_baseline",
        creditedPoints:0,creditedSocialCoins:0,
        creditedLevelXp:0,creditedLeagueXp:0,
        emulatorOnly:true});
    }
    activeFenceFixture(fence,account,migration);
    // IMPORTANT: no server credit for a share event created BEFORE the
    // separately reviewed account-specific cutover effective timestamp.
    // Second phone must have separately reviewed server-only enrollment.
    // This additional gate does NOT prove actual old published APK revocation.
    await validateReviewedCutoverEpochInTransaction({
      reader,migration,account,currentSession,
      sourceCreatedAtMs:created,serverNowMs
    });
    activeVerifiedSourceAction(proof,account,shareId,dayId,eventKey,
      serverNowMs,created);
    // Stage46: an ORIGINAL cross-account SHARE is not independently sufficient
    // to prove the original phone-local award. Require a distinct migration
    // reviewer fixture AND a server-HMAC signed task CLAIM, all read again in
    // this SAME atomic Firestore transaction. No signed proof -> no grant.
    await validateSignedTaskClaimInTransaction({
      reader,accountKey:account,dayId,eventKey,originalShareId:shareId,
      sourceCreatedAtMs:created,serverNowMs,
      migrationId:migration.migrationId,backendSecret
    });
    // Stage49: the mobile-writable session installId/trustedInstallIds
    // are NONAUTHORITATIVE. Require independent backend-UID+App binding,
    // reviewed in THIS SAME transaction, before any XP/coin/league write.
    await validateServerUidBindingInTransaction({
      reader,request,accountKey:account,
      migrationId:migration.migrationId,serverNowMs,backendSecret
    });
    // A replay from another already-trusted device is a no-op.
    if(existingStateEvent!==null){
      if(existingReceipt===null||
         !core.sameEvent(core.parseReceipt(existingReceipt,account),receipt)||
         existingStateEvent.eventKey!==eventKey||
         !core.sameEvent(core.parseReceipt(existingStateEvent.receipt,account),receipt)||
         !valid(existingStateEvent.appliedVersion)||
         existingStateEvent.appliedVersion<1||
         existingStateEvent.appliedVersion>state.version)
        fail("conflicting_or_partial_replay");
      if(existingLeague!==null&&
         (existingLeague.eventKey!==eventKey||
          existingLeague.amount!==20||
          existingLeague.accountKey!==account))
        fail("conflicting_league_replay");
      return Object.freeze({outcome:"already_awarded",
        creditedPoints:0,creditedSocialCoins:0,
        creditedLevelXp:0,creditedLeagueXp:0,
        emulatorOnly:true});
    }
    if(existingReceipt!==null||existingLeague!==null)
      fail("orphan_or_preexisting_receipt");
    const next=core.applyEvent(state,receipt);
    const leagueEligible=clock.phase==="active"&&
      created<clock.current.closeAtMs;
    // All reads are complete BEFORE any writes.
    const stamped={format:1,accountKey:account,eventKey,
      receipt,receiptId:eventKey,appliedVersion:next.version,
      afterBalances:next.balances,createdAtMs:serverNowMs,
      emitter:"stage49_server_uid_bound_original_task_atomic_emulator_only"};
    tx.create(db.doc("deda_progress_receipts/"+account+"/events/"+eventKey),
      receipt);
    tx.create(db.doc("deda_verified_progress/"+account+"/events/"+eventKey),
      stamped);
    tx.update(db.doc("deda_verified_progress/"+account),next);
    if(leagueEligible){
      tx.create(db.doc(LEAGUE_ROOT+"/"+clock.current.weekId+"_"+eventKey),{
        emulatorOnly:true,issuer:ISSUER,accountKey:account,
        weekId:clock.current.weekId,dayId,eventKey,
        taskId:TASK,amount:20,createdAtMs:serverNowMs,
      });
    }
    return Object.freeze({outcome:"private_atomic_award",
      creditedPoints:5,creditedSocialCoins:10,creditedLevelXp:20,
      creditedLeagueXp:leagueEligible?20:0,
      emulatorOnly:true,realFirebaseDeployment:false});
  });
  for(let attempt=0;attempt<3;attempt++){
    try{return await applyOnce();}
    catch(e){
      if(attempt===2||e?.code!==3||
         !/Transaction is invalid or closed/.test(e?.message||""))
        throw e;
    }
  }
  fail("emulator_transaction_retry_exhausted");
}
module.exports=Object.freeze({PROJECT,ISSUER,FENCE_ISSUER,
  ACTION_ROOT,FENCE_ROOT,LEAGUE_ROOT,simulateMigratedTaskAndLeagueAtomic});
