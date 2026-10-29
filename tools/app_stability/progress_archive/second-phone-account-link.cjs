"use strict";
/**
 * Emulated, UNDEPLOYED canonical-account link on a second phone. This is a
 * real idempotent server transaction, but NOT a financial restoration:
 * it stores only the verified account pointer, NEVER copies XP, purchases,
 * diamonds, level, frame, ID, friend or league scores from another UID.
 *
 * Must NOT be exported by functions/index.js. Enabling in production needs
 * independently verified Auth/App Check, old writer cutover, asset/receipt
 * settlement and owner approval. Legacy PIN+install identity is inadequate.
 */
const core=require("./reconcile-core.cjs");
const {replayServerLedger}=require("./cross-device-readiness-audit.cjs");
const {readOwnedEntitlements}=require("./second-phone-entitlements-readonly.cjs");
const {parseMigration,validateSettlement}=require("./migration-gate.cjs");
const {parseDeployment,validateFence,deploymentPath}=
 require("./activate-reviewed-baseline.cjs");
const {createHash}=require("node:crypto");
const PROJECT="demo-deda-restore-readiness";
const ACCOUNT=/^[0-9]{10,16}$/;
const UID=/^[A-Za-z0-9_-]{8,128}$/;
const ID=/^[A-Za-z0-9_-]{20,80}$/;
const stamp=v=>v&&Number.isSafeInteger(v.seconds)&&
 Number.isSafeInteger(v.nanoseconds)&&v.nanoseconds>=0&&v.nanoseconds<1e9;
function fail(x){throw Error("DEDA_ACCOUNT_LINK_"+x);}
function guard(){
 if(process.env.GCLOUD_PROJECT!==PROJECT||
    process.env.DEDA_RESTORE_AUDIT_EMULATOR_ONLY!=="true"||
    process.env.FIRESTORE_EMULATOR_HOST!=="127.0.0.1:8080")
   fail("REFUSE_PRODUCTION");
}
function binding(b,uid,accountKey){
 return !!b&&b.uid===uid&&b.accountKey===accountKey&&
  b.authProvider==="anonymous"&&
  b.state==="LOCAL_VERIFIED_HOLD_ONLY"&&b.emulatorOnly===true&&
  b.canMigrate===false&&b.canGrant===false&&stamp(b.createdAt);
}
function response(replayed,progress,entitlements){
 // Fresh, independently replayed server values; these are DISPLAY-ONLY.
 // They are never a client-side spend authorization or a migration receipt.
 const state=core.parseState(progress,progress.accountKey);
 return Object.freeze({
   status:"ACCOUNT_LINKED_READONLY_EMULATOR_ONLY",
   replayed,emulatorOnly:true,
   verifiedEntitlements:entitlements,
   verifiedProgress:Object.freeze({
     format:1,version:state.version,
     points:state.balances.points,coins:state.balances.coins,
     xp:state.balances.xp,earnedDiamonds:state.balances.earnedDiamonds,
     spendable:false,entitlementsVerified:false,
   }),
   canRestoreFinancialBalances:false,canCreditXp:false,
   canCreditDiamonds:false,canRestoreFrames:false,
   canRestorePremiumId:false,canIssueLeagueGift:false,
   productionReady:false,
 });
}
async function linkSecondPhoneToCanonicalAccount({
 store,auth,idToken,accountKey,oldUid,newUid,linkId
}={}){
 guard();
 if(!store||typeof store.runTransaction!=="function"||
    typeof store.serverTimestamp!=="function"||
    !auth||typeof auth.verifyIdToken!=="function"||
    typeof auth.getUser!=="function"||
    typeof idToken!=="string"||idToken.length<16||
    !ACCOUNT.test(accountKey||"")||
    !UID.test(oldUid||"")||!UID.test(newUid||"")||
    oldUid===newUid||!ID.test(linkId||""))
   fail("INVALID_REQUEST");
 // Authenticate the NEW phone's actual Firebase UID, no caller-asserted
 // identity, copied install ID, raw PIN or unverified provider permitted.
 let token,person;
 try{
   token=await auth.verifyIdToken(idToken,true);
   if(token?.uid!==newUid||
      token?.firebase?.sign_in_provider!=="anonymous")
     fail("UNVERIFIED_AUTH");
   person=await auth.getUser(newUid);
   if(person?.uid!==newUid||person.disabled===true||
      !!person.email||person.providerData?.length>0)
     fail("UNVERIFIED_AUTH");
 }catch(_){fail("UNVERIFIED_AUTH");}
 return store.runTransaction(async tx=>{
   guard();
   const get=path=>tx.get(path);
   const root="deda_progress_migrations/"+accountKey;
   const linkPath="deda_private_second_phone_links/"+newUid;
   const [directory,profile,oldBinding,newBinding,migration,verified,prior]=
     await Promise.all([
       get("deda_account_directory/"+accountKey),
       get("deda_account_profiles/"+accountKey),
       get("deda_stage54_private_account_bindings/"+oldUid),
       get("deda_stage54_private_account_bindings/"+newUid),
       get(root),get("deda_verified_progress/"+accountKey),
       get(linkPath),
     ]);
   if(directory?.accountKey!==accountKey||directory?.active!==true||
      directory?.createdUid!==oldUid||
      profile?.accountKey!==accountKey||
      !binding(oldBinding,oldUid,accountKey)||
      !binding(newBinding,newUid,accountKey))
     fail("SERVER_ACCOUNT_PROOF_MISSING");
   let phase,progress;
   try{
     phase=parseMigration(migration,accountKey);
     progress=core.parseState(verified,accountKey);
   }catch(_){fail("REVIEWED_PROGRESS_NOT_READY");}
   if(phase.phase!=="cutover-complete"||
      phase.settlementId===null||
      progress.initializedBy!==phase.baselineEventKey)
     fail("REVIEWED_PROGRESS_NOT_READY");
   const [resolution,settlement,deploy,activation]=await Promise.all([
     get(root+"/settlementReviews/"+phase.settlementId),
     get(root+"/settlements/"+phase.settlementId),
     get(deploymentPath),
     get(root+"/activations/"+phase.migrationId),
   ]);
   let deployment;
   try{deployment=parseDeployment(deploy);}catch(_){
     fail("TRUSTED_CUTOVER_UNVERIFIED");
   }
   // The settlement is a reviewed *account* state, not a purchase/ID
   // entitlement. It can never authorize client-side wallet mutation.
   if(!resolution||resolution.accountKey!==accountKey||
      resolution.migrationId!==phase.migrationId||
      resolution.settlementId!==phase.settlementId||
      resolution.status!=="resolved"||
      resolution.pendingPurchases!==0||
      resolution.pendingReservations!==0||
      !activation||activation.accountKey!==accountKey||
      activation.migrationId!==phase.migrationId||
      activation.settlementId!==phase.settlementId||
      activation.baselineEventKey!==phase.baselineEventKey||
      activation.deploymentRevision!==deployment.revision||
      activation.enforcementRevision!==deployment.enforcementRevision||
      !settlement)
     fail("TRUSTED_CUTOVER_UNVERIFIED");
   try{validateSettlement(settlement,phase);}
   catch(_){fail("TRUSTED_CUTOVER_UNVERIFIED");}
   // An approval document with zero pending purchases is not proof that
   // original installed clients have actually lost write authority.
   const fenceRecord=await get(root+"/fences/"+resolution.legacyFenceId);
   try{validateFence(fenceRecord,phase,resolution,deployment);}
   catch(_){fail("LEGACY_FINANCIAL_WRITER_NOT_FENCED");}
   // The account pointer must not be issued from an unverified projection.
   // Replay EVERY signed source event against its independent server receipt
   // in THIS SAME transaction before creating the canonical second-phone
   // link. A missing query API, incomplete page or concurrent source drift
   // holds the link rather than copying phantom XP or diamonds.
   let fullLedgerVerified=false;
   if(typeof tx.list==="function"){
     try{
       fullLedgerVerified=await replayServerLedger({
         get:path=>tx.get(path),
         list:(path,args)=>tx.list(path,args),
       },accountKey,progress);
     }catch(_){fullLedgerVerified=false;}
   }
   if(!fullLedgerVerified)fail("RECEIPT_CHAIN_NOT_RECONCILED");
   // All known receipt-backed inventory and premium-ID registry proofs are
   // read in the same account-link transaction. Native frame purchases are
   // preserved as UNREVIEWED, not fabricated into owned inventory.
   let entitlements;
   try{
     entitlements=await readOwnedEntitlements(
       {get:path=>tx.get(path)},accountKey,resolution.originalId);
   }catch(_){fail("ENTITLEMENT_OWNERSHIP_RECONCILIATION_REQUIRED");}
   // The personal DEDA identifier is permanently tied to the ACCOUNT, not
   // the old anonymous Firebase installation. The second phone must already
   // have a verified profile and original ID; this is never inferred from
   // caller-supplied identity, balance, installId or premium ID.
   const personalIdPath="deda_share_ids/"+resolution.originalId;
   const [personalIdRoute,newUser]=await Promise.all([
     get(personalIdPath),get("users/"+newUid),
   ]);
   if(personalIdRoute?.publicId!==resolution.originalId||
      personalIdRoute?.kind!=="personal"||personalIdRoute.active!==true||
      newUser?.accountKey!==accountKey||
      newUser?.sharePersonalId!==resolution.originalId||
      !["string"].includes(typeof personalIdRoute.ownerUid))
     fail("ORIGINAL_ID_NEW_PHONE_PROFILE_NOT_VERIFIED");
   // First takeover must still belong to original UID. Repeated same-phone
   // links must be owned by the linked UID; never override another device.
   if(personalIdRoute.ownerUid!==(prior===null?oldUid:newUid))
     fail("ORIGINAL_ID_CONCURRENT_OWNER_TAKEOVER");
   const writerFencePath="deda_migration_spend_authority/"+resolution.originalId;
   const oldWriterFence=await get(writerFencePath);
   const accountFencePath="deda_migration_account_authority/"+accountKey;
   const oldAccountFence=await get(accountFencePath);
   const writerFence={
     format:1,publicId:resolution.originalId,
     originalUid:oldUid,activeUid:newUid,status:"new-device-exclusive",
     protocol:"deda-verified-progress-v1",migrationId:phase.migrationId,
     deploymentRevision:deployment.revision,
   };
   const accountFence={
     format:1,accountKey,originalUid:oldUid,activeUid:newUid,
     status:"new-device-exclusive",protocol:"deda-verified-progress-v1",
     migrationId:phase.migrationId,deploymentRevision:deployment.revision,
   };
   if(oldAccountFence!==null){
     const {createdAt,...stored}=oldAccountFence;
     if(!stamp(createdAt)||
       Object.keys(stored).length!==Object.keys(accountFence).length||
       !Object.entries(accountFence).every(([key,value])=>stored[key]===value))
       fail("SECOND_PHONE_CONFLICTING_ACCOUNT_WRITER_FENCE");
   }
   if(oldWriterFence!==null){
     const {createdAt,...stored}=oldWriterFence;
     if(!stamp(createdAt)||
        Object.keys(stored).length!==Object.keys(writerFence).length||
        !Object.entries(writerFence).every(([key,value])=>stored[key]===value))
       fail("SECOND_PHONE_CONFLICTING_OLD_WRITER_FENCE");
   }
   const payload={
      format:1,accountKey,oldUid,newUid,linkId,
      migrationId:phase.migrationId,
      // Link a canonical account, not a frozen balance/version. Real XP can
      // legitimately change between logins; revisiting the same phone must
      // not create a new account or duplicate any earned progress.
      progressInitializedBy:progress.initializedBy,
      reviewedDeploymentRevision:deployment.revision,
      mode:"readonly-account-link-v1",
      canCreditDiamonds:false,canCreditXp:false,
      canTransferEntitlements:false,canIssueGift:false,
      emulatorOnly:true,
   };
   const digest=createHash("sha256").update(JSON.stringify(payload)).digest("hex");
   if(prior!==null){
     if(oldWriterFence===null || oldAccountFence===null)
       fail("SECOND_PHONE_LINK_WITHOUT_WRITER_FENCE");
     const {createdAt,...rest}=prior;
     if(!stamp(createdAt)||rest.digest!==digest||
        Object.keys(rest).length!==Object.keys(payload).length+1||
        !Object.entries(payload).every(([k,v])=>rest[k]===v))
       fail("SECOND_PHONE_EXISTING_LINK_CONFLICT");
     return response(true,progress,entitlements);
   }
   // The account pointer and exclusive-wallet-writer marker are installed
   // in ONE atomic emulator-only transaction; an older phone's client writes
   // are denied only WHEN the separately reviewed Firestore rule candidate is
   // deployed. Neither marker can mint, debit or grant any item.
   if(oldWriterFence!==null||oldAccountFence!==null)
     fail("SECOND_PHONE_WRITER_FENCE_ALREADY_PREPARED");
   tx.set(linkPath,{...payload,digest,createdAt:store.serverTimestamp()});
   tx.set(writerFencePath,{...writerFence,createdAt:store.serverTimestamp()});
   tx.set(accountFencePath,{...accountFence,createdAt:store.serverTimestamp()});
   // Server-authoritative owner handover; original @DEDA identifier is
   // preserved, never replaced by a second profile or duplicated.
   // This is not an entitlement grant and is emulator-guarded.
   tx.set(personalIdPath,{...personalIdRoute,ownerUid:newUid,
     updatedAt:store.serverTimestamp()});
   return response(false,progress,entitlements);
 });
}
module.exports={linkSecondPhoneToCanonicalAccount};
