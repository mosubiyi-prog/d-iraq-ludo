"use strict";

/**
 * DEDA جمال التطبيق المتكاملة — Stage30 SERVER ENDPOINT DRAFT (NOT DEPLOYED).
 *
 * Transport for an AdMob-shaped SSV callback, but NO wallet writes and NO
 * provider-origin certification. It uses Stage22 OFFLINE GENERATED FAKE key
 * verifier only for local tests. The owner AdMob console currently reads
 * 5 DEDA Points with NO callback URL; Stage22 fake reward is 1 diamonds.
 *
 * NEVER expose this entrypoint via production functions/index.js. Testing
 * restricted to localhost Firestore Emulator demo project; a real Firebase
 * invocation fails closed. No real callback URL exists from this file.
 */
const {verifyProviderSignedCallback}=
  require("./deda_jamal_stage22_admob_ssv_ecdsa_staged_no_deploy_2026_10_19.js");
const {
  CONSOLE_SNAPSHOT,DEMO_EXPECTED,
}=require("./deda_jamal_stage29_console_reward_contract_vs_diamond_gate_2026_10_19.js");

const DEMO_PROJECT="demo-deda-stage22-ssv-fakeprovider";
const PATH="/deda-stage30-ssv-offline";
const MAX_URL=4200;
const MAX_QUERY=4096;
const RESPONSE_HEADER=Object.freeze({
  "Cache-Control":"no-store, no-cache, max-age=0",
  "Pragma":"no-cache",
  "X-Content-Type-Options":"nosniff",
});
function exactDemoRuntime(){
  return /^(127[.]0[.]0[.]1|localhost):[0-9]+$/.test(
      process.env.FIRESTORE_EMULATOR_HOST||"") &&
    process.env.GCLOUD_PROJECT===DEMO_PROJECT;
}
function safeReply(res,status,code){
  for(const [key,value] of Object.entries(RESPONSE_HEADER)){
    res.setHeader(key,value);
  }
  res.statusCode=status;
  res.setHeader("Content-Type","application/json; charset=utf-8");
  res.end(JSON.stringify({ok:false,code,
    creditedDiamonds:0,creditedPoints:0,
    productionVerification:false}));
}
function rawCallbackQuery(req){
  // Express/Firebase originalUrl is required to preserve raw signed bytes.
  // Do NOT use req.query, URLSearchParams.toString or decoded/reordered URL.
  if(!req || typeof req.originalUrl!=="string" ||
      req.originalUrl.length>MAX_URL) return {code:413};
  if(req.originalUrl.includes("#") ||
      req.originalUrl.includes("\r") ||
      req.originalUrl.includes("\n") ||
      req.originalUrl.includes("\\") ||
      !req.originalUrl.startsWith(PATH+"?"))return {code:400};
  const raw=req.originalUrl.slice(PATH.length+1);
  if(!raw || raw.length>MAX_QUERY || raw.includes("?"))return {code:400};
  return {raw};
}
function createOfflineSsvHttpReceiver({
  testPinnedPublicKeys,
  // Dependency injection only for OFFLINE locally-generated fake keys.
}={}){
  return function stage30OfflineReceiver(req,res){
    // Critical: MUST precede parsing, crypto, task/cache/Firestore access.
    if(!exactDemoRuntime()){
      safeReply(res,503,"GOOGLE_SSV_OFFICIAL_ORIGIN_NOT_CONFIGURED");
      return;
    }
    if(!req || req.method!=="GET"){
      safeReply(res,405,"EXPECTED_PROVIDER_GET_ONLY");return;
    }
    const extracted=rawCallbackQuery(req);
    if(!extracted.raw){
      safeReply(res,extracted.code===413?413:400,
        "INVALID_RAW_SIGNED_CALLBACK_TRANSPORT");return;
    }
    if(!testPinnedPublicKeys ||
        Object.getPrototypeOf(testPinnedPublicKeys)!==Object.prototype ||
        Object.keys(testPinnedPublicKeys).length===0){
      safeReply(res,503,"NO_TRUSTED_OFFLINE_TEST_KEY");return;
    }
    let event;
    try {
      event=verifyProviderSignedCallback(
        extracted.raw,testPinnedPublicKeys);
    } catch (_) {
      // No raw signature, nonce, key ID or device details in response/logs.
      safeReply(res,422,"UNVERIFIED_OR_UNSUPPORTED_PROVIDER_CALLBACK");
      return;
    }
    // Even a valid generated EC test key cannot prove Google origin.
    // The owner's 5 DEDA Points does not match Stage22's 1 diamonds.
    const ownerUnitMatch=event.adUnitId===CONSOLE_SNAPSHOT.adUnitId;
    const demoRewardMatch=event.rewardAmount===DEMO_EXPECTED.rewardAmount &&
      event.rewardItem===DEMO_EXPECTED.rewardItem;
    if(!ownerUnitMatch||!demoRewardMatch){
      safeReply(res,409,"TEST_SIGNED_EVENT_UNIT_OR_POLICY_MISMATCH");
      return;
    }
    // No 2xx responses, wallet credits, real payout, signed receipts or
    // actual callback acceptance while Google SSV is not configured.
    safeReply(res,409,"OFFLINE_SIGNATURE_IS_NOT_GOOGLE_SSV");
  };
}
function buildStagedSsvFirebaseDefinitions({
  onRequest,onCall,HttpsError,testPinnedPublicKeys,
}={}){
  if(typeof onRequest!=="function"||typeof onCall!=="function"||
      typeof HttpsError!=="function"){
    throw new TypeError("Firebase HTTPS v2 factories required");
  }
  // Neither function is exported in functions/index.js. The caller and
  // publisher must explicitly approve export and deployment in a later stage.
  const issueDemoChallenge=onCall({
    enforceAppCheck:true,
    memory:"256MiB",
    timeoutSeconds:15,
    maxInstances:1,
  },async(_request)=>{
    // Do not offer issuance with fake signature scheme or live client,
    // regardless of auth and AppCheck. A future reviewed callable will
    // exclusively derive UID from request.auth.uid and AppCheck appId.
    throw new HttpsError("unavailable",
      "REAL_GOOGLE_SSV_AND_ACCOUNT_BOUND_NONCE_NOT_YET_READY");
  });
  const callback=onRequest({
    timeoutSeconds:15,
    memory:"256MiB",
    maxInstances:1,
    cors:false,
  },createOfflineSsvHttpReceiver({testPinnedPublicKeys}));
  return Object.freeze({issueDemoChallenge,callback,
    exportedToProduction:false,
    deployable:false,
    googleOriginVerified:false});
}
module.exports={
  createOfflineSsvHttpReceiver,buildStagedSsvFirebaseDefinitions,
  rawCallbackQuery,exactDemoRuntime,
};
