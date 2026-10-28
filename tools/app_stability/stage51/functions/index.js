"use strict";
/**
 * Stage51 private transport-only Firebase Functions emulator entrypoint.
 * NOT in DEDA's production functions/index.js, not an APK, not deployable.
 *
 * Read-only Auth diagnostic validates the Firebase AUTH EMULATOR's real
 * Auth-EMULATOR-ISSUED (unsigned, test-only) ID-token transport in the Functions Emulator. App Check
 * preflight is the UNMODIFIED Stage50 guard, with enforceAppCheck + replay
 * token consumption options. App Check service does NOT have a comparable
 * full token-attestation emulator: this test must never claim an actual
 * production App Check token/hardware has been verified.
 *
 * No task issuer, progress, league, wallets, gifts or live Firebase writes.
 */
const {onCall,HttpsError}=require("firebase-functions/v2/https");
const {initializeApp}=require("firebase-admin/app");
const {getFirestore}=require("firebase-admin/firestore");
const {
 makeStage50ReadOnlyPreflightCallable
}=require("../../../../functions/deda_weekly_stage50_auth_appcheck_readonly_preflight_NOT_EXPORTED.js");
initializeApp({projectId:"demo-deda-stage51-auth-functions-qa"});
const db=getFirestore();

exports.dedaStage51AuthOnlyProbe=onCall({
  enforceAppCheck:false,timeoutSeconds:15,memory:"256MiB"
},async request=>{
  if(!request.auth?.uid||
     request.auth?.token?.firebase?.sign_in_provider==="anonymous")
    throw new HttpsError("unauthenticated","real-firebase-auth-emulator-token-required");
  if(!request.data||typeof request.data!=="object"||
     Array.isArray(request.data)||
     Object.keys(request.data).length!==0)
    throw new HttpsError("invalid-argument","server-derived-empty-request-only");
  return {
    component:"DEDA_STAGE51_AUTH_TOKEN_TRANSPORT_QA_ONLY",
    readOnly:true,verifiedByLocalAuthEmulator:true,
    // Return no ID/phone, account/UID, token, balances or rank.
    awardState:"HOLD_NO_GRANTS",
    canCreditTaskPoints:false,canCreditLifetimeXp:false,
    canCreditSocialCoins:false,canCreditLeagueXp:false,
    canIssueWinnerGift:false,canCreditDiamonds:false,
    productionRewardReady:false,realAppCheckDeviceVerified:false,
  };
});
exports.dedaStage51ProtectedPreflight=makeStage50ReadOnlyPreflightCallable({
 onCall,HttpsError,db,
 approvedAppIds:["stage51_test_app_check_fixture"],
 serverClock:()=>Date.now()
});
