"use strict";
/**
 * Stage50: real Firebase Functions V2 onCall transport *DECLARATION* for
 * read-only DEDA account cutover preflight. NOT exported from functions/index.
 *
 * The platform, WHEN DEPLOYED, verifies Firebase ID token and App Check token
 * before populating request.auth/request.app. Tests invoke the handler with
 * SYNTHETIC contexts and DO NOT prove live token/App Check verification.
 *
 * The original app/client can update deda_sessions.installId and
 * deda_account_profiles.trustedInstallIds under deployed Rules. They are
 * NOT server evidence of device identity, task completion or old APK cutoff.
 * All real task, league XP, social coins, gifts and diamonds remain OFF.
 *
 * Never claim this is deployable without an owner-approved version migration,
 * App Check client integration, Auth config, attestation, historical-wallet
 * reconciliation and rollback. No live Firestore rules/Cloud Function writes.
 */
const ACCOUNT=/^[0-9]{10,16}$/;
const UID=/^[A-Za-z0-9_-]{1,128}$/;
const APP=/^[A-Za-z0-9:._-]{6,160}$/;
const REQUIRED_OPTIONS=Object.freeze({
  enforceAppCheck:true,
  consumeAppCheckToken:true,
  timeoutSeconds:20,
  memory:"256MiB",
});
const TASK="DEDA_WEEKLY_STAGE50_READ_ONLY_PREFLIGHT";
const BLOCKERS=Object.freeze([
  "real-original-task-claim-issuer-not-enabled",
  "historic-cross-phone-credit-settlement-not-approved",
  "old-installed-apk-server-write-cutover-not-verified",
  "backend-winner-gifts-not-activated",
  "owner-pre-apk-review-pending",
]);
function isPlain(x){
  return x!==null&&typeof x==="object"&&!Array.isArray(x)&&
    (Object.getPrototypeOf(x)===Object.prototype||
      Object.getPrototypeOf(x)===null);
}
function records(record,uid){
  return record&&typeof record==="object"&&!Array.isArray(record)&&
    (record.uid===undefined||record.uid===uid);
}
function makeStage50ReadOnlyPreflightCallable({
  onCall,HttpsError,db,approvedAppIds,serverClock=()=>Date.now()
}){
  if(typeof onCall!=="function"||typeof HttpsError!=="function"||
     !db||typeof db.doc!=="function"||
     !Array.isArray(approvedAppIds)||
     approvedAppIds.length===0||
     !approvedAppIds.every(a=>typeof a==="string"&&APP.test(a))||
     new Set(approvedAppIds).size!==approvedAppIds.length||
     typeof serverClock!=="function")
    throw Error("STAGE50_SERVER_CONFIGURATION_MISSING");
  const appSet=new Set(approvedAppIds);
  const error=(code,message)=>{throw new HttpsError(code,message);};
  // ACTUAL firebase-functions/v2 onCall options, but declared only in a
  // TEST MODULE. We never attach it to the production functions/index.js.
  return onCall({...REQUIRED_OPTIONS},async(request)=>{
    const uid=request?.auth?.uid;
    const appId=request?.app?.appId;
    if(!UID.test(uid||"")||
       request?.auth?.token?.firebase?.sign_in_provider==="anonymous")
      error("unauthenticated","deda-account-auth-required");
    if(typeof appId!=="string"||!appSet.has(appId))
      error("permission-denied","deda-verified-app-required");
    if(!isPlain(request.data)||Object.keys(request.data).length!==0)
      error("invalid-argument","deda-server-derived-readonly-request-only");
    const now=serverClock();
    if(!Number.isSafeInteger(now)||now<0)
      error("unavailable","deda-server-clock-unavailable");
    let user,session,profile;
    try{
      const [userSnap,sessionSnap]=await Promise.all([
        db.doc("users/"+uid).get(),
        db.doc("deda_sessions/"+uid).get()
      ]);
      if(!userSnap.exists||!sessionSnap.exists)
        error("failed-precondition","deda-account-requires-review");
      user=userSnap.data();session=sessionSnap.data();
      const account=user?.accountKey;
      if(!ACCOUNT.test(account||"")||!records(user,uid)||
         !records(session,uid)||session.accountKey!==account)
        error("failed-precondition","deda-account-requires-review");
      const profileSnap=await db.doc("deda_account_profiles/"+account).get();
      if(!profileSnap.exists)
        error("failed-precondition","deda-account-requires-review");
      profile=profileSnap.data();
      if(profile?.accountKey!==account)
        error("failed-precondition","deda-account-requires-review");
    }catch(e){
      if(e instanceof HttpsError)throw e;
      // No raw auth tokens, account identifiers, balances, or user input
      // are logged or reflected. Never fail open on backend read errors.
      error("unavailable","deda-readonly-preflight-unavailable");
    }
    // Client-controlled install and trustedInstallIds are intentionally
    // IGNORED here. Even consistent account documents never prove a claim.
    void profile;
    return Object.freeze({
      schema:1,component:TASK,readOnly:true,
      authorizedAccountRecordExists:true,
      authenticatedAppContextPresent:true,
      awardState:"HOLD_NO_GRANTS",
      canCreditTaskPoints:false,
      canCreditLifetimeXp:false,
      canCreditSocialCoins:false,
      canCreditLeagueXp:false,
      canIssueWinnerGift:false,
      canCreditDiamonds:false,
      realOldApkRevocationVerified:false,
      productionRewardReady:false,
      blockers:[...BLOCKERS],
      // Never expose accountKey, UID, phone/install ID, original balances
      // or public DEDA ID via this readiness endpoint.
    });
  });
}
module.exports=Object.freeze({
  REQUIRED_OPTIONS,TASK,BLOCKERS,
  makeStage50ReadOnlyPreflightCallable
});
