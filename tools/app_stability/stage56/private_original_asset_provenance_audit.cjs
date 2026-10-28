"use strict";
/*
 * Stage56: standalone SERVER-ONLY, NO-TRANSFER provenance audit.
 * Reads exact existing DEDA legacy schema in an isolated Firestore emulator.
 * Requires an immutable Stage55 HOLD, re-verifies the original Stage55 source
 * HMAC against CURRENT original snapshots, then records one private Stage56 HOLD.
 *
 * Source visibility != payment proof, gift proof, or account ownership.
 * NO task/XP/wallet/ID/frame/gift writes; no real users or cloud deploy.
 */
const crypto=require("node:crypto");
const {PROJECT,ROOT:PREVIOUS_ROOT}=require("../stage55/private_two_phone_migration_hold.cjs");
const ROOT="deda_stage56_private_asset_provenance_holds";
const ACCOUNT=/^[0-9]{8,15}$/,UID=/^[A-Za-z0-9_-]{8,128}$/;
const CAPTURE=/^[A-Za-z0-9_-]{20,80}$/,HEX=/^[a-f0-9]{64}$/;
const ORIGINAL_ID=/^@DEDA-[A-Za-z0-9_-]{3,32}$/;
const block=reason=>{throw new Error("DEDA_STAGE56_HOLD_BLOCK_"+reason);};
const canonical=value=>{
  if(value===null||typeof value!=="object")return value;
  if(typeof value.toMillis==="function")return {millis:value.toMillis()};
  if(Array.isArray(value))return value.map(canonical);
  return Object.fromEntries(Object.keys(value).sort().map(k=>[k,canonical(value[k])]));
};
const digest=(key,data)=>crypto.createHmac("sha256",key).update(data).digest("hex");
const obj=s=>s.exists?s.data():null;
const sorted=values=>[...new Set(values)].sort();
const falseFlags=()=>({
  canMigrate:false,canTransferAccount:false,canTransferWallet:false,
  canTransferFrames:false,canReplacePremiumId:false,canCreditXp:false,
  canCreditDiamonds:false,canIssueGift:false,canSettlePurchase:false,
  productionReady:false,
});
function guard({db,serverKey,accountKey,originalUid,newPhoneUid,purchaseCaptureId,receiptId,giftId,originalPersonalId}){
  if(process.env.GCLOUD_PROJECT!==PROJECT||
    process.env.FIRESTORE_EMULATOR_HOST!=="127.0.0.1:8080"||
    process.env.DEDA_STAGE56_EMULATOR_ONLY!=="true"||
    process.env.DEDA_STAGE55_EMULATOR_ONLY!=="true"||
    !Buffer.isBuffer(serverKey)||serverKey.length<32||
    !db||typeof db.runTransaction!=="function")block("EMULATOR_ONLY");
  if(!ACCOUNT.test(accountKey||"")||!UID.test(originalUid||"")||
     !UID.test(newPhoneUid||"")||originalUid===newPhoneUid||
     !CAPTURE.test(purchaseCaptureId||"")||
     !HEX.test(receiptId||"")||!HEX.test(giftId||"")||
     !ORIGINAL_ID.test(originalPersonalId||""))block("INVALID_SERVER_INPUT");
}
function auditSources(s){
  const flags=["STAGE55_LEGACY_HOLD_NOT_RELEASED",
    "NO_PAYMENT_PROVIDER_VERIFIED_RECEIPT",
    "NO_INDEPENDENT_DIAMOND_BALANCE_PROOF",
    "NO_SIGNED_ID_OR_FRAME_OWNERSHIP_TRANSFER_PROOF",
    "LOCAL_TASK_XP_COINS_UNTRUSTED",
    "APP_CHECK_AND_OLD_APP_CUTOVER_UNVERIFIED"];
  const status={
    purchase:"MISSING_LEGACY_PURCHASE_CAPTURE",
    progress:"MISSING_PROGRESS_MIGRATION_RECORD",
    receipt:"MISSING_NOMINATED_PROGRESS_RECEIPT",
    state:"MISSING_VERIFIED_PROGRESS_STATE",
    gift:"MISSING_PRIVATE_GIFT_FIXTURE",
    originalId:"MISSING_ORIGINAL_SHARE_ID_ROW",
  };
  if(s.purchase){
    status.purchase="UNTRUSTED_CLIENT_PURCHASE_JOURNAL";
    flags.push("PURCHASE_JOURNAL_IS_NOT_PAYMENT_PROVIDER_RECEIPT");
    if(s.purchase.accountKey!==s.accountKey||
       s.purchase.kind!=="legacy-purchase-evidence"||
       s.purchase.sourceUid!==s.originalUid)
      flags.push("PURCHASE_CAPTURE_OWNER_OR_KIND_CONFLICT");
  }
  if(s.migration){
    status.progress="UNVERIFIED_SERVER_MIGRATION_CANDIDATE";
    if(s.migration.accountKey!==s.accountKey)
      flags.push("MIGRATION_ACCOUNT_CONFLICT");
    if(s.migration.phase!=="cutover-complete")
      flags.push("MIGRATION_CUTOVER_NOT_COMPLETE");
    else flags.push("CUTOVER_LABEL_ALONE_CANNOT_PROVE_ORIGINAL_SETTLEMENT");
  }
  if(s.receipt){
    status.receipt="UNVERIFIED_RECEIPT_CANDIDATE";
    if(s.receipt.accountKey!==s.accountKey)
      flags.push("RECEIPT_ACCOUNT_CONFLICT");
    flags.push("RECEIPT_MUST_BE_REVIEWED_WITH_SIGNED_SERVER_ISSUER_AND_BASELINE");
  }
  if(s.state){
    status.state="UNVERIFIED_PROGRESS_STATE_CANDIDATE";
    if(s.state.accountKey!==s.accountKey)
      flags.push("PROGRESS_STATE_ACCOUNT_CONFLICT");
  }
  if(s.gift){
    status.gift="PRIVATE_QA_GIFT_NOT_SPENDABLE";
    flags.push("STAGE45_PRIVATE_GIFT_NEVER_AUTHORISES_LIVE_DIAMONDS");
    if(s.gift.emulatorOnly!==true||s.gift.canAuthorizeProduction!==false)
      flags.push("PRIVATE_GIFT_FORGED_OR_NON_QA_SHAPE");
  }
  if(s.alias){
    status.originalId="LEGACY_ALIAS_NOT_INDEPENDENT_OWNERSHIP_PROOF";
    if(s.alias.ownerUid!==s.originalUid||
       s.alias.kind!=="personal"||s.alias.active!==true)
      flags.push("PERSONAL_ID_LEGACY_OWNER_CONFLICT");
  }
  if(s.originalWallet?.premiumId!==s.newWallet?.premiumId)
    flags.push("TWO_PHONE_PREMIUM_ID_DIFFERENCE");
  if(JSON.stringify(canonical(s.originalWallet?.purchasedFrames??null))!==
     JSON.stringify(canonical(s.newWallet?.purchasedFrames??null)))
    flags.push("TWO_PHONE_PURCHASED_FRAME_DIFFERENCE");
  if(s.originalWallet?.diamonds!==s.newWallet?.diamonds)
    flags.push("TWO_PHONE_DIAMONDS_DIFFERENCE");
  // Flags are diagnostics only; NO positive authorization signal possible.
  return {holdFlags:sorted(flags),sourceStatus:status};
}
async function auditAssetProvenance(args){
  guard(args);
  const {db,serverKey,accountKey,originalUid,newPhoneUid,
    purchaseCaptureId,receiptId,giftId,originalPersonalId}=args;
  const token=digest(serverKey,"account:"+accountKey);
  const existing=db.doc(ROOT+"/"+token);
  const hold=db.doc(PREVIOUS_ROOT+"/"+token);
  const originalBinding=db.doc("deda_stage54_private_account_bindings/"+originalUid);
  const newBinding=db.doc("deda_stage54_private_account_bindings/"+newPhoneUid);
  const dir=db.doc("deda_account_directory/"+accountKey);
  const profile=db.doc("deda_account_profiles/"+accountKey);
  const oldUser=db.doc("users/"+originalUid);
  const newUser=db.doc("users/"+newPhoneUid);
  const oldWallet=db.doc("users/"+originalUid+"/wallet/original");
  const newWallet=db.doc("users/"+newPhoneUid+"/wallet/original");
  const oldSession=db.doc("deda_sessions/"+originalUid);
  const newSession=db.doc("deda_sessions/"+newPhoneUid);
  const purchase=db.doc("deda_purchase_evidence/"+accountKey+"/captures/"+purchaseCaptureId);
  const migration=db.doc("deda_progress_migrations/"+accountKey);
  const progress=db.doc("deda_verified_progress/"+accountKey);
  const receipt=db.doc("deda_progress_receipts/"+accountKey+"/events/"+receiptId);
  const gift=db.doc("deda_weekly_stage45_private_gift_inbox/"+giftId);
  const alias=db.doc("deda_share_ids/"+originalPersonalId);
  return db.runTransaction(async tx=>{
    // ALL reads before the sole optional private report create.
    const results=await Promise.all([
      existing,hold,originalBinding,newBinding,dir,profile,
      oldUser,newUser,oldWallet,newWallet,oldSession,newSession,
      purchase,migration,progress,receipt,gift,alias
    ].map(r=>tx.get(r)));
    const [previous,stage55,b1,b2,directory,owner,u1,u2,w1,w2,
      se1,se2,purchaseSnap,migrationSnap,progressSnap,receiptSnap,giftSnap,aliasSnap]=
      results.map(obj);
    if(!stage55||stage55.state!=="HOLD_MANUAL_REVIEW_ONLY"||
       stage55.emulatorOnly!==true||stage55.canMigrate!==false||
       stage55.canTransferWallet!==false||
       stage55.originalUid!==originalUid||stage55.newPhoneUid!==newPhoneUid||
       stage55.accountDigest!==token||!HEX.test(stage55.stateDigest||""))
      block("MISSING_IMMUTABLE_STAGE55_HOLD");
    for(const [uid,b] of [[originalUid,b1],[newPhoneUid,b2]])
      if(!b||b.uid!==uid||b.accountKey!==accountKey||
         b.authProvider!=="anonymous"||
         b.state!=="LOCAL_VERIFIED_HOLD_ONLY"||
         b.emulatorOnly!==true||b.canMigrate!==false||
         b.canGrant!==false)block("MISSING_SERVER_HOLD_BINDING");
    if(!directory||directory.accountKey!==accountKey||directory.active!==true||
       !owner||owner.accountKey!==accountKey)
      block("MISSING_ORIGINAL_CANONICAL_ACCOUNT");
    const source=[
      {uid:originalUid,accountKey,user:u1,wallet:w1,session:se1},
      {uid:newPhoneUid,accountKey,user:u2,wallet:w2,session:se2}
    ];
    const stage55Current=digest(serverKey,JSON.stringify(canonical({
      accountKey,uidPair:[originalUid,newPhoneUid],source,
      profile:owner,directory,bindings:[b1,b2]
    })));
    if(stage55Current!==stage55.stateDigest)
      block("PREVIOUS_STAGE55_SOURCE_DRIFT");
    const evidence={
      accountKey,originalUid,
      originalWallet:w1,newWallet:w2,
      purchase:purchaseSnap,migration:migrationSnap,state:progressSnap,
      receipt:receiptSnap,gift:giftSnap,alias:aliasSnap,
    };
    const analyzed=auditSources(evidence);
    const evidenceDigest=digest(serverKey,JSON.stringify(canonical({
      stage55Digest:stage55.stateDigest,
      purchaseCaptureId,receiptId,giftId,originalPersonalId,
      purchaseSnap,migrationSnap,progressSnap,receiptSnap,giftSnap,aliasSnap,
    })));
    if(previous){
      if(previous.evidenceDigest!==evidenceDigest||
         previous.stage55Digest!==stage55.stateDigest||
         previous.originalUid!==originalUid||
         previous.newPhoneUid!==newPhoneUid||
         JSON.stringify(previous.sourceStatus)!==
           JSON.stringify(analyzed.sourceStatus))
        block("PREVIOUS_AUDIT_PROVENANCE_CHANGED");
      return Object.freeze({status:"ALREADY_HOLD",reportId:token,
        ...falseFlags(),sourceStatus:previous.sourceStatus,
        holdFlags:previous.holdFlags});
    }
    const result={
      format:1,issuer:"stage56_private_emulator_provenance_audit_NOT_LIVE",
      state:"HOLD_UNVERIFIED_ASSET_ORIGIN",
      emulatorOnly:true,
      ...falseFlags(),
      accountDigest:token,originalUid,newPhoneUid,
      stage55Digest:stage55.stateDigest,evidenceDigest,
      sourceStatus:analyzed.sourceStatus,
      holdFlags:analyzed.holdFlags,
      // NO original account number, PIN, ID, balance, frames, coins or snapshot.
    };
    tx.create(existing,result);
    return Object.freeze({
      status:"NEW_HOLD",reportId:token,...falseFlags(),
      sourceStatus:result.sourceStatus,holdFlags:result.holdFlags
    });
  },{maxAttempts:5});
}
module.exports={ROOT,auditAssetProvenance};
