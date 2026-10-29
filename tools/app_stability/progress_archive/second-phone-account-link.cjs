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
const {parseMigration}=require("./migration-gate.cjs");
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
function response(replayed){
 return Object.freeze({
   status:"ACCOUNT_LINKED_READONLY_EMULATOR_ONLY",
   replayed,emulatorOnly:true,
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
   const [resolution,fence,deploy,activation]=await Promise.all([
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
      !fence||fence.accountKey!==accountKey||
      fence.baselineEventKey!==phase.baselineEventKey||
      fence.pendingPurchases!==0||fence.pendingReservations!==0)
     fail("TRUSTED_CUTOVER_UNVERIFIED");
   const payload={
      format:1,accountKey,oldUid,newUid,linkId,
      migrationId:phase.migrationId,
      progressVersion:progress.version,
      progressInitializedBy:progress.initializedBy,
      reviewedDeploymentRevision:deployment.revision,
      mode:"readonly-account-link-v1",
      canCreditDiamonds:false,canCreditXp:false,
      canTransferEntitlements:false,canIssueGift:false,
      emulatorOnly:true,
   };
   const digest=createHash("sha256").update(JSON.stringify(payload)).digest("hex");
   if(prior!==null){
     const {createdAt,...rest}=prior;
     if(!stamp(createdAt)||rest.digest!==digest||
        Object.keys(rest).length!==Object.keys(payload).length+1||
        !Object.entries(payload).every(([k,v])=>rest[k]===v))
       fail("SECOND_PHONE_EXISTING_LINK_CONFLICT");
     return response(true);
   }
   // Atomic with other account link candidates, fail on competing writers.
   // Absolutely no users/{uid}, wallet, receipts or league data writes.
   tx.set(linkPath,{...payload,digest,createdAt:store.serverTimestamp()});
   return response(false);
 });
}
module.exports={linkSecondPhoneToCanonicalAccount};
