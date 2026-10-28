"use strict";
/*
 * Stage57: REAL local Auth Emulator -> Functions v2 Emulator -> unchanged
 * original Firestore Rules (Admin SDK only). Read-only original-anonymous
 * DEDA migration preflight with Stage54/55/56 private HOLD chain.
 *
 * This file is NEVER exported from live functions/index.js and cannot
 * grant, migrate, settle, copy user data or prove production App Check.
 * Firebase Auth Emulator JWTs are UNSIGNED TEST FIXTURES. This is NOT a
 * production token-attestation, Play Integrity or original APK test.
 */
const crypto=require("node:crypto");
const {onCall,HttpsError}=require("firebase-functions/v2/https");
const {initializeApp}=require("firebase-admin/app");
const {getAuth}=require("firebase-admin/auth");
const {getFirestore}=require("firebase-admin/firestore");
const PROJECT="demo-deda-stage55-two-phone-hold";
const ACCOUNT=/^[0-9]{8,15}$/;
const HEX=/^[a-f0-9]{64}$/;
initializeApp({projectId:PROJECT});
const db=getFirestore();
function stop(){
  throw new HttpsError("permission-denied","original-account-migration-review-required");
}
function ensureLocalOnly(){
  const k=process.env.STAGE57_EMULATOR_KEY_HEX;
  if(process.env.GCLOUD_PROJECT!==PROJECT||
     process.env.DEDA_STAGE57_EMULATOR_ONLY!=="true"||
     process.env.DEDA_STAGE55_EMULATOR_ONLY!=="true"||
     process.env.DEDA_STAGE56_EMULATOR_ONLY!=="true"||
     !process.env.FIREBASE_AUTH_EMULATOR_HOST||
     !process.env.FIREBASE_FUNCTIONS_EMULATOR_HOST||
     process.env.FIRESTORE_EMULATOR_HOST!=="127.0.0.1:8080"||
     typeof k!=="string"||!HEX.test(k))
    throw new HttpsError("failed-precondition","STAGE57_EMULATOR_ONLY_PRODUCTION_REFUSED");
  return Buffer.from(k,"hex");
}
function canonical(value){
  if(value===null||typeof value!=="object")return value;
  if(typeof value.toMillis==="function")return {millis:value.toMillis()};
  if(Array.isArray(value))return value.map(canonical);
  return Object.fromEntries(Object.keys(value).sort().map(k=>[k,canonical(value[k])]));
}
const hash=(key,message)=>crypto.createHmac("sha256",key).update(message).digest("hex");
const value=s=>s.exists?s.data():null;
const noGrants=()=>Object.freeze({
  schema:1,
  component:"STAGE57_ORIGINAL_ANONYMOUS_UID_BACKEND_PREFLIGHT_EMULATOR_ONLY",
  state:"HOLD_NEEDS_PRODUCTION_VERIFIED_AUTH_AND_APP_CHECK",
  readOnly:true,emulatorOnly:true,
  productionReady:false,productionAppCheckVerified:false,
  verifiedOriginalPhoneOwnership:false,verifiedOldApkCutover:false,
  verifiedAssetSettlement:false,
  canMigrate:false,canTransferAccount:false,canTransferWallet:false,
  canTransferFrames:false,canReplacePremiumId:false,
  canCreditTaskPoints:false,canCreditLifetimeXp:false,
  canCreditSocialCoins:false,canCreditLeagueXp:false,
  canCreditDiamonds:false,canIssueWinnerGift:false,
  canSettlePurchase:false,
  // No account/UID/phone/pin/install ID, wallet, XP, ID or rank returned.
});
exports.dedaStage57OriginalAnonymousMigrationReadOnlyPreflight=onCall({
  // Auth Emulator anonymous ID token is test-only.
  // Real AppCheck attestation is NOT available in this emulator, so this
  // endpoint can only return HOLD, never an actual transfer authorization.
  enforceAppCheck:false,timeoutSeconds:30,memory:"256MiB"
},async request=>{
  const key=ensureLocalOnly();
  if(!request.auth?.uid||
     request.auth.token?.firebase?.sign_in_provider!=="anonymous"||
     !request.data||typeof request.data!=="object"||
     Array.isArray(request.data)||Object.keys(request.data).length!==0)
    stop();
  const uid=request.auth.uid;
  let emulatorUser=null;
  try{emulatorUser=await getAuth().getUser(uid);}catch(_){stop();}
  if(!emulatorUser||emulatorUser.disabled||emulatorUser.email||
     emulatorUser.providerData?.length)stop();

  // Derive canonical account from server-only Stage54 binding, NEVER from
  // request.data, old device install ID, client-writable sessions or user row.
  const callerBinding=await db.doc("deda_stage54_private_account_bindings/"+uid).get();
  const c=value(callerBinding),account=c?.accountKey;
  if(!ACCOUNT.test(account||"")||c.uid!==uid||
     c.emulatorOnly!==true||c.canMigrate!==false||
     c.canGrant!==false||c.authProvider!=="anonymous"||
     c.state!=="LOCAL_VERIFIED_HOLD_ONLY")stop();
  const token=hash(key,"account:"+account);

  try{
    const result=await db.runTransaction(async tx=>{
      const ref=n=>db.doc(n);
      const paths=[
        "deda_stage55_private_two_phone_hold_reports/"+token,
        "deda_stage56_private_asset_provenance_holds/"+token,
      ];
      const [stage55Snap,stage56Snap]=await Promise.all(paths.map(p=>tx.get(ref(p))));
      const s55=value(stage55Snap),s56=value(stage56Snap);
      if(!s55||!s56||s55.state!=="HOLD_MANUAL_REVIEW_ONLY"||
         s56.state!=="HOLD_UNVERIFIED_ASSET_ORIGIN"||
         s55.emulatorOnly!==true||s56.emulatorOnly!==true||
         s55.accountDigest!==token||s56.accountDigest!==token||
         s56.stage55Digest!==s55.stateDigest||
         !HEX.test(s55.stateDigest||"")||!HEX.test(s56.evidenceDigest||"")||
         ![s55.originalUid,s55.newPhoneUid].includes(uid)||
         s56.originalUid!==s55.originalUid||
         s56.newPhoneUid!==s55.newPhoneUid||
         !Array.isArray(s55.holdFlags)||
         !Array.isArray(s56.holdFlags)||
         !s56.holdFlags.includes("NO_PAYMENT_PROVIDER_VERIFIED_RECEIPT")||
         !s56.holdFlags.includes("APP_CHECK_AND_OLD_APP_CUTOVER_UNVERIFIED"))
        return false;
      for(const o of [s55,s56])
        for(const flag of ["canMigrate","canTransferWallet","canTransferFrames",
           "canTransferAccount","canReplacePremiumId","canCreditXp",
           "canCreditDiamonds","canIssueGift"])
          if(o[flag]!==false)return false;
      if(s56.canSettlePurchase!==false||s56.productionReady!==false)
        return false;
      const old=s55.originalUid,now=s55.newPhoneUid;
      const sourcePaths=[
        "deda_stage54_private_account_bindings/"+old,
        "deda_stage54_private_account_bindings/"+now,
        "deda_account_directory/"+account,
        "deda_account_profiles/"+account,
        "users/"+old,"users/"+now,
        "users/"+old+"/wallet/original",
        "users/"+now+"/wallet/original",
        "deda_sessions/"+old,"deda_sessions/"+now
      ];
      const snapshots=await Promise.all(sourcePaths.map(path=>tx.get(ref(path))));
      const [bOld,bNew,dir,profile,uOld,uNew,wOld,wNew,sOld,sNew]=
        snapshots.map(value);
      for(const [owner,b] of [[old,bOld],[now,bNew]])
        if(!b||b.uid!==owner||b.accountKey!==account||
           b.authProvider!=="anonymous"||b.emulatorOnly!==true||
           b.state!=="LOCAL_VERIFIED_HOLD_ONLY"||
           b.canMigrate!==false||b.canGrant!==false)
          return false;
      if(!dir||dir.accountKey!==account||dir.active!==true||
         !profile||profile.accountKey!==account)return false;
      const source=[
        {uid:old,accountKey:account,user:uOld,wallet:wOld,session:sOld},
        {uid:now,accountKey:account,user:uNew,wallet:wNew,session:sNew},
      ];
      const currentFingerprint=hash(key,JSON.stringify(canonical({
        accountKey:account,uidPair:[old,now],source,
        profile,directory:dir,bindings:[bOld,bNew]
      })));
      if(currentFingerprint!==s55.stateDigest)return false;
      return true;
    },{maxAttempts:3});
    if(result!==true)stop();
  }catch(error){
    if(error instanceof HttpsError)throw error;
    throw new HttpsError("unavailable","original-account-preflight-unavailable");
  }
  return noGrants();
});
