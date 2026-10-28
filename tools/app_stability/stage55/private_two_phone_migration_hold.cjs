"use strict";
/*
 * STAGE55 = SERVER-ONLY TWO-PHONE LEGACY MIGRATION HOLD REPORT
 * LOCAL FIRESTORE EMULATOR QA ONLY. Not exported by production Functions.
 * No wallet, identity, XP, ownership, purchase or user writes ever.
 *
 * This audit DOES NOT infer grants from mobile-local points, install IDs,
 * mutable sessions, profile IDs, client wallet balances or Stage54's QA binding.
 * It creates exactly one immutable, non-authorizing server-private HOLD record
 * per canonical account. Source changes reject replay rather than overwriting.
 */
const crypto=require("node:crypto");
const PROJECT="demo-deda-stage55-two-phone-hold";
const ROOT="deda_stage55_private_two_phone_hold_reports";
const ACCOUNT=/^[0-9]{8,15}$/;
const UID=/^[a-zA-Z0-9_-]{8,128}$/;
const fail=(reason)=>{
  const e=new Error("DEDA_STAGE55_MIGRATION_HOLD_"+reason);
  e.code="DEDA_STAGE55_HOLD_BLOCK";
  throw e;
};
function guard(key){
  if(process.env.GCLOUD_PROJECT!==PROJECT||
     process.env.FIRESTORE_EMULATOR_HOST!=="127.0.0.1:8080"||
     process.env.DEDA_STAGE55_EMULATOR_ONLY!=="true"||
     !Buffer.isBuffer(key)||key.length<32)
    fail("EMULATOR_ONLY");
}
const digest=(secret,value)=>
 crypto.createHmac("sha256",secret).update(value).digest("hex");
const data=s=>s.exists?s.data():null;
function canonical(value){
  if(value===null||typeof value!=="object")return value;
  if(typeof value.toMillis==="function")return {millis:value.toMillis()};
  if(Array.isArray(value))return value.map(canonical);
  return Object.fromEntries(Object.keys(value).sort().map(k=>[k,canonical(value[k])]));
}
function safeScalar(value){
  if(value===undefined||value===null)return null;
  if(typeof value==="string"||typeof value==="number"||typeof value==="boolean")return value;
  return JSON.stringify(canonical(value));
}
function compareLegacy(first,second){
  const flags=new Set([
    "NO_AUTOMATIC_LEGACY_BALANCE_TRUST",
    "LOCAL_DAILY_POINTS_CANNOT_BE_SERVER_VERIFIED",
    "CLIENT_WRITABLE_OLD_SESSIONS_AND_INSTALL_IDS",
    "NO_PRODUCTION_APP_CHECK_OR_OLD_APK_CUTOVER",
    "STAGE54_ANONYMOUS_PIN_BINDING_IS_EMULATOR_ONLY",
    "NO_INDEPENDENT_PURCHASE_OR_GIFT_PROVENANCE",
  ]);
  if(!first?.user||!second?.user)flags.add("MISSING_UID_LEGACY_USER_ROW");
  if(!first?.wallet||!second?.wallet)flags.add("MISSING_UID_WALLET_SNAPSHOT");
  const keys=[
    "diamonds","xp","coins","level","premiumId","personalId",
    "sharePersonalId","purchasedFrames","ownedFrames","frames"
  ];
  for(const key of keys){
    const vals=[first,second].map(x=>
      safeScalar(x?.wallet?.[key]??x?.user?.[key]));
    if(vals[0]!==vals[1])flags.add("TWO_PHONE_"+key.toUpperCase()+"_MISMATCH");
  }
  for(const [device,item] of [["original",first],["new",second]]){
    if(!item.user)continue;
    if(item.user.uid!=null&&item.user.uid!==item.uid)
      flags.add("USER_UID_MISMATCH_"+device.toUpperCase());
    if(item.user.accountKey!==item.accountKey)
      flags.add("USER_ACCOUNT_MISMATCH_"+device.toUpperCase());
    if(item.session?.accountKey!==item.accountKey ||
       item.session?.uid!==item.uid)
      flags.add("LEGACY_SESSION_MISMATCH_"+device.toUpperCase());
  }
  return [...flags].sort();
}
async function migrationHold({db,accountKey,originalUid,newPhoneUid,serverKey}){
  guard(serverKey);
  if(typeof accountKey!=="string"||!ACCOUNT.test(accountKey)||
     typeof originalUid!=="string"||!UID.test(originalUid)||
     typeof newPhoneUid!=="string"||!UID.test(newPhoneUid)||
     originalUid===newPhoneUid)fail("INVALID_TWO_UID_INPUT");
  if(!db || typeof db.runTransaction!=="function")fail("ADMIN_DB_REQUIRED");
  const accountDigest=digest(serverKey,"account:"+accountKey);
  const target=db.doc(ROOT+"/"+accountDigest);
  const originalBinding=db.doc("deda_stage54_private_account_bindings/"+originalUid);
  const newBinding=db.doc("deda_stage54_private_account_bindings/"+newPhoneUid);
  const directory=db.doc("deda_account_directory/"+accountKey);
  const profile=db.doc("deda_account_profiles/"+accountKey);
  const userOne=db.doc("users/"+originalUid),userTwo=db.doc("users/"+newPhoneUid);
  const walletOne=db.doc("users/"+originalUid+"/wallet/original");
  const walletTwo=db.doc("users/"+newPhoneUid+"/wallet/original");
  const sessionOne=db.doc("deda_sessions/"+originalUid);
  const sessionTwo=db.doc("deda_sessions/"+newPhoneUid);
  return db.runTransaction(async tx=>{
    // 11 transaction reads BEFORE any writes. Immutable snapshots + HOLD only.
    const snaps=await Promise.all([
      tx.get(target),tx.get(originalBinding),tx.get(newBinding),
      tx.get(directory),tx.get(profile),
      tx.get(userOne),tx.get(userTwo),tx.get(walletOne),tx.get(walletTwo),
      tx.get(sessionOne),tx.get(sessionTwo)
    ]);
    const [previous,firstBind,secondBind,dir,owner,firstUser,secondUser,
      firstWallet,secondWallet,firstSession,secondSession]=snaps.map(data);
    // Never let a caller's installId, old writable session or a local task
    // snapshot be used as proof of canonical ownership. This only accepts
    // the server-namespace *sandbox* binding from tested Stage54.
    for(const [uid,b] of [[originalUid,firstBind],[newPhoneUid,secondBind]]){
      if(!b||b.uid!==uid||b.accountKey!==accountKey||
         b.authProvider!=="anonymous"||
         b.state!=="LOCAL_VERIFIED_HOLD_ONLY"||
         b.emulatorOnly!==true||b.canMigrate!==false||
         b.canGrant!==false)fail("MISSING_STAGE54_SERVER_HOLD_BINDING");
    }
    if(!dir||dir.accountKey!==accountKey||dir.active!==true||
       !owner||owner.accountKey!==accountKey)
      fail("CANONICAL_ACCOUNT_OR_PROFILE_MISSING");
    const source=[
      {uid:originalUid,accountKey,user:firstUser,wallet:firstWallet,session:firstSession},
      {uid:newPhoneUid,accountKey,user:secondUser,wallet:secondWallet,session:secondSession}
    ];
    const flags=compareLegacy(source[0],source[1]);
    const stateDigest=digest(serverKey,JSON.stringify(canonical({
      accountKey,uidPair:[originalUid,newPhoneUid],
      source,profile:owner,directory:dir,
      bindings:[firstBind,secondBind],
    })));
    if(previous){
      if(previous.stateDigest!==stateDigest ||
         previous.originalUid!==originalUid ||
         previous.newPhoneUid!==newPhoneUid)
        fail("PREVIOUS_IMMUTABLE_REPORT_CHANGED_SOURCE_REQUIRES_REVIEW");
      // Never increment gifts or XP on a retry. Do not modify existing report.
      return {
        status:"ALREADY_HOLD",reportId:accountDigest,
        flags:previous.holdFlags,canMigrate:false,
        canCreditXp:false,canCreditDiamonds:false,canIssueGift:false,
        canReplacePremiumId:false,
      };
    }
    // Server-side Admin writes ONLY to a NEW PRIVATE HOLD document.
    // Report contains no legacy balance/PII, raw PIN, installId or purchase.
    const report={
      format:1,issuer:"stage55-private-emulator-audit-NOT_LIVE",
      state:"HOLD_MANUAL_REVIEW_ONLY",
      emulatorOnly:true,canMigrate:false,canCreditXp:false,
      canCreditDiamonds:false,canIssueGift:false,
      canReplacePremiumId:false,canTransferWallet:false,
      canTransferFrames:false,canTransferAccount:false,
      accountDigest,originalUid,newPhoneUid,stateDigest,
      sourceUserRowsPresent:source.filter(x=>x.user!==null).length,
      sourceWalletRowsPresent:source.filter(x=>x.wallet!==null).length,
      holdFlags:flags,
      // Intentionally no "approved" or original wallet snapshot.
    };
    tx.create(target,report);
    return {
      status:"NEW_HOLD",reportId:accountDigest,flags,
      canMigrate:false,canCreditXp:false,
      canCreditDiamonds:false,canIssueGift:false,
      canReplacePremiumId:false,
    };
  },{maxAttempts:5});
}
module.exports={PROJECT,ROOT,migrationHold};
