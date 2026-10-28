"use strict";
/*
 * STAGE58 / LOCAL-ONLY TWO-PHONE MIGRATION REHEARSAL, NOT A MIGRATION.
 * Admin SDK Firestore Emulator ONLY. No production handler, auth entitlement,
 * wallet, XP, bought frame, premium ID, admin or gift writes.
 * A SHA/HMAC-bound private plan can be created and then terminally ABORTED.
 * Abort is of this INERT PLAN ONLY; it does NOT test real-wallet rollback.
 *
 * Stage56's source report lacks the original purchase/gift capture IDs,
 * so Stage58 explicitly CANNOT revalidate all payment/evidence provenance.
 * Even with matched two-phone snapshots we always HOLD; no "approve" path.
 */
const crypto=require("node:crypto");
const {PROJECT,ROOT:ROOT55}=require("../stage55/private_two_phone_migration_hold.cjs");
const {ROOT:ROOT56}=require("../stage56/private_original_asset_provenance_audit.cjs");
const ROOT="deda_stage58_private_cross_phone_rehearsal_plans";
const ACCOUNT=/^[0-9]{8,15}$/;
const UID=/^[A-Za-z0-9_-]{8,128}$/;
const HEX=/^[a-f0-9]{64}$/;
const fail=why=>{throw new Error("DEDA_STAGE58_HOLD_"+why);};
const H=(key,s)=>crypto.createHmac("sha256",key).update(s).digest("hex");
const val=s=>s.exists?s.data():null;
function canonical(v){
  if(v===null||typeof v!=="object")return v;
  if(typeof v.toMillis==="function")return {millis:v.toMillis()};
  if(Array.isArray(v))return v.map(canonical);
  return Object.fromEntries(Object.keys(v).sort().map(k=>[k,canonical(v[k])]));
}
const noWrites=()=>({
  emulatorOnly:true,productionReady:false,approved:false,
  canMigrate:false,canTransferAccount:false,canTransferWallet:false,
  canTransferFrames:false,canTransferPremiumId:false,
  canCreditXp:false,canCreditSocialCoins:false,canCreditDiamonds:false,
  canIssueGift:false,canSettlePurchase:false,oldApkWriterFenced:false,
  productionAppCheckVerified:false,sourcePaymentProofVerified:false,
  realWalletRollbackPerformed:false,dataMoved:false,
});
function guard({db,accountKey,originalUid,newPhoneUid,serverKey,action}){
  if(process.env.GCLOUD_PROJECT!==PROJECT||
     process.env.FIRESTORE_EMULATOR_HOST!=="127.0.0.1:8080"||
     process.env.DEDA_STAGE55_EMULATOR_ONLY!=="true"||
     process.env.DEDA_STAGE56_EMULATOR_ONLY!=="true"||
     process.env.DEDA_STAGE58_EMULATOR_ONLY!=="true"||
     !Buffer.isBuffer(serverKey)||serverKey.length<32||
     !db||typeof db.runTransaction!=="function")
    fail("REFUSE_OUTSIDE_LOCAL_EMULATOR");
  if(typeof accountKey!=="string"||!ACCOUNT.test(accountKey)||
     typeof originalUid!=="string"||!UID.test(originalUid)||
     typeof newPhoneUid!=="string"||!UID.test(newPhoneUid)||
     originalUid===newPhoneUid||
     !["prepare","abort"].includes(action))
    fail("INVALID_BACKEND_REHEARSAL_INPUT");
}
function publicView(record,repeat){
  return Object.freeze({
    status:record.status==="ABORTED_NO_TRANSFER"?"ABORTED_NO_TRANSFER":
      repeat?"ALREADY_HELD":"NEW_HOLD",
    reportId:record.accountDigest,
    blockers:record.blockers,
    rollbackPlanOnly:record.status==="ABORTED_NO_TRANSFER",
    ...noWrites(),
  });
}
async function rehearseTwoPhoneHold(args){
  guard(args);
  const {db,accountKey,originalUid,newPhoneUid,serverKey,action}=args;
  const accountDigest=H(serverKey,"account:"+accountKey);
  const uidPairDigest=H(serverKey,
    JSON.stringify(["uids",originalUid,newPhoneUid]));
  const planRef=db.doc(ROOT+"/"+accountDigest);
  return db.runTransaction(async tx=>{
    // Every Firestore read happens before every write.
    const oldPlanSnap=await tx.get(planRef),prior=val(oldPlanSnap);
    if(action==="abort"){
      if(!prior)fail("NO_PLAN_TO_ABORT");
      if(prior.accountDigest!==accountDigest||
         prior.uidPairDigest!==uidPairDigest||
         prior.emulatorOnly!==true||prior.dataMoved!==false||
         !["HOLD_PREPARED","ABORTED_NO_TRANSFER"].includes(prior.status))
        fail("ABORT_REFUSED_PLAN_IDENTITY_OR_SHAPE");
      if(prior.status==="ABORTED_NO_TRANSFER")
        return publicView(prior,true);
      const terminal={
        status:"ABORTED_NO_TRANSFER",abortReason:
          "SOURCE_UNVERIFIED_OR_OWNER_RELEASE_NOT_APPROVED",
        rollbackPlanOnly:true,
        realWalletRollbackPerformed:false,dataMoved:false,
      };
      tx.update(planRef,terminal);
      return publicView({...prior,...terminal},false);
    }
    // For prepare, verify original Stage54/55/56 HOLD and read two-phone
    // source IN THE SAME TRANSACTION to fence changes.
    const refs=[
      "deda_stage55_private_two_phone_hold_reports/"+accountDigest,
      "deda_stage56_private_asset_provenance_holds/"+accountDigest,
      "deda_stage54_private_account_bindings/"+originalUid,
      "deda_stage54_private_account_bindings/"+newPhoneUid,
      "deda_account_directory/"+accountKey,
      "deda_account_profiles/"+accountKey,
      "users/"+originalUid,"users/"+newPhoneUid,
      "users/"+originalUid+"/wallet/original",
      "users/"+newPhoneUid+"/wallet/original",
      "deda_sessions/"+originalUid,"deda_sessions/"+newPhoneUid
    ];
    const [s55,s56,b1,b2,directory,profile,u1,u2,w1,w2,se1,se2]=
      (await Promise.all(refs.map(p=>tx.get(db.doc(p))))).map(val);
    if(!s55||s55.state!=="HOLD_MANUAL_REVIEW_ONLY"||
       !s56||s56.state!=="HOLD_UNVERIFIED_ASSET_ORIGIN"||
       s55.emulatorOnly!==true||s56.emulatorOnly!==true||
       s55.accountDigest!==accountDigest||s56.accountDigest!==accountDigest||
       s55.originalUid!==originalUid||s55.newPhoneUid!==newPhoneUid||
       s56.originalUid!==originalUid||s56.newPhoneUid!==newPhoneUid||
       !HEX.test(s55.stateDigest||"")||
       !HEX.test(s56.evidenceDigest||"")||
       s56.stage55Digest!==s55.stateDigest||
       !Array.isArray(s56.holdFlags)||
       !s56.holdFlags.includes("NO_PAYMENT_PROVIDER_VERIFIED_RECEIPT")||
       !s56.holdFlags.includes("APP_CHECK_AND_OLD_APP_CUTOVER_UNVERIFIED"))
      fail("IMMUTABLE_PREVIOUS_HOLD_NOT_VALID");
    for(const old of [s55,s56])
      for(const k of ["canMigrate","canTransferWallet","canTransferFrames",
        "canTransferAccount","canReplacePremiumId","canCreditXp",
        "canCreditDiamonds","canIssueGift"])
        if(old[k]!==false)fail("PRIOR_HOLD_INVARIANT_TAMPERED");
    if(s56.canSettlePurchase!==false||s56.productionReady!==false)
      fail("ASSET_APPROVAL_TAMPERED");
    for(const [uid,b] of [[originalUid,b1],[newPhoneUid,b2]])
      if(!b||b.uid!==uid||b.accountKey!==accountKey||
         b.authProvider!=="anonymous"||b.emulatorOnly!==true||
         b.state!=="LOCAL_VERIFIED_HOLD_ONLY"||
         b.canMigrate!==false||b.canGrant!==false)
        fail("INVALID_PRIVILEGED_UID_BINDING");
    if(!directory||directory.active!==true||
       directory.accountKey!==accountKey||
       !profile||profile.accountKey!==accountKey)
      fail("CANONICAL_LEGACY_ACCOUNT_MISSING");
    const source=[
      {uid:originalUid,accountKey,user:u1,wallet:w1,session:se1},
      {uid:newPhoneUid,accountKey,user:u2,wallet:w2,session:se2}
    ];
    const fingerprint=H(serverKey,JSON.stringify(canonical({
      accountKey,uidPair:[originalUid,newPhoneUid],source,
      profile,directory,bindings:[b1,b2]
    })));
    if(s55.stateDigest!==fingerprint)
      fail("LEGACY_SOURCE_CHANGED_AFTER_STAGE55_HOLD");
    const blockers=[
      "ORIGINAL_AUTH_UNATTESTED_IN_PRODUCTION",
      "NO_PRODUCTION_APP_CHECK_AND_OLD_APK_CUTOVER",
      "NO_INDEPENDENT_RECEIPT_AND_PAYMENT_SETTLEMENT",
      "STAGE56_EVIDENCE_SOURCES_CANNOT_BE_REHASHED_FROM_REPORT",
      "NO_INDEPENDENT_PREMIUM_ID_AND_FRAME_OWNERSHIP_PROOF",
      "NO_VERIFIED_LEVEL_XP_COIN_TRANSFER_OR_ROLLBACK",
      "OWNER_PRE_APK_REVIEW_AND_DEVICE_QA_PENDING"
    ];
    const evidenceDigest=H(serverKey,JSON.stringify([
      "stage58-rehearsal-only-v1",s55.stateDigest,s56.evidenceDigest,
      uidPairDigest,blockers
    ]));
    if(prior){
      if(prior.uidPairDigest!==uidPairDigest||
         prior.evidenceDigest!==evidenceDigest||
         prior.stage55Digest!==s55.stateDigest||
         prior.stage56Digest!==s56.evidenceDigest||
         prior.dataMoved!==false||prior.emulatorOnly!==true||
         !["HOLD_PREPARED","ABORTED_NO_TRANSFER"].includes(prior.status))
        fail("EXISTING_REHEARSAL_CONFLICT_PRESERVE_OLD");
      return publicView(prior,true);
    }
    const report={
      schema:1,issuer:"stage58-local-private-rehearsal-NOT_LIVE",
      status:"HOLD_PREPARED",accountDigest,uidPairDigest,
      stage55Digest:s55.stateDigest,stage56Digest:s56.evidenceDigest,
      evidenceDigest,blockers,
      rollbackPlanOnly:false,
      ...noWrites(),
    };
    tx.create(planRef,report);
    return publicView(report,false);
  },{maxAttempts:5});
}
module.exports={ROOT,rehearseTwoPhoneHold};
