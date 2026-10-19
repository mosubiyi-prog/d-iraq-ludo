"use strict";

/**
 * DEDA Jamal Stage28 — REPOSITORY-ONLY AdMob configuration trace.
 * Source review cannot establish AdMob console settings, officially signed
 * Google callbacks, the exact code installed on owner phone, or deploy rights.
 * Never import into production functions/index.js or Flutter main.dart.
 * No network, reward grant, Firestore, or production writes.
 */

const {readFileSync}=require("node:fs");
const {resolve}=require("node:path");

const root=resolve(__dirname,"..");
const sourceFiles=Object.freeze({
  appIdPatch:"tools/apply_real_admob_ids_100257_2026_10_03.py",
  diamondRewardPatch:"tools/add_diamonds_reward_100259_2026_10_04.py",
  taskRewardPatch:"tools/rewarded_ad_resilience_100258_2026_10_03.py",
  originalRealAdBuild:".github/workflows/build-closed-test-real-admob-100257.yml",
  stage22SyntheticVerifierTest:
    "test/deda_jamal_stage22_signed_provider_callback_firestore_emulator.test.js",
  actualMainUnpatched:"lib/main.dart",
  functionsIndex:"functions/index.js",
});

function loadRepoSources(){
  const output={};
  for(const [name,path] of Object.entries(sourceFiles)){
    output[name]=readFileSync(resolve(root,path),"utf8");
  }
  return Object.freeze(output);
}
function parseOnePythonString(src,name){
  const match=src.match(new RegExp("^"+name+
    "\\s*=\\s*['\\\"]([^'\\\"\\r\\n]+)['\\\"]\\s*$","m"));
  if(!match)throw Object.assign(
    new Error("missing-expected-admob-configuration:"+name),{
      code:"failed-precondition",
    });
  return match[1];
}
function detectSourceReadiness(sources){
  if(!sources||typeof sources!=="object"||
      Object.keys(sourceFiles).some(name=>
        typeof sources[name]!=="string")){
    throw Object.assign(new Error("reviewable-repository-sources-required"),{
      code:"failed-precondition",
    });
  }
  const adApp=parseOnePythonString(sources.appIdPatch,"REAL_APP_ID");
  const adUnit=parseOnePythonString(sources.appIdPatch,"REAL_REWARDED_ID");
  const testAdUnit=parseOnePythonString(sources.appIdPatch,"TEST_REWARDED_ID");
  const appMatch=adApp.match(/^ca-app-pub-([0-9]{16})~([0-9]{10})$/);
  const unitMatch=adUnit.match(/^ca-app-pub-([0-9]{16})\/([0-9]{10})$/);
  if(!appMatch || !unitMatch || appMatch[1]!==unitMatch[1] ||
      adUnit===testAdUnit){
    throw Object.assign(new Error("real-admob-app-unit-ids-do-not-align"),{
      code:"failed-precondition",
    });
  }

  const checks=Object.freeze({
    realUnitConfiguredInPatch:sources.appIdPatch.includes(
      "main.replace(TEST_REWARDED_ID, REAL_REWARDED_ID)"),
    oldBuildActuallyAppliesRealId:sources.originalRealAdBuild.includes(
      "python3 tools/apply_real_admob_ids_100257_2026_10_03.py"),
    stagedTestAdUnitMatchesBuild:
      sources.stage22SyntheticVerifierTest.includes(
        'adUnitId:"'+adUnit+'"'),
    diamondsAreThreePerAd:
      sources.diamondRewardPatch.includes(
        "static const int rewardPerAd = 3;"),
    diamondsCappedFivePerLocalDay:
      sources.diamondRewardPatch.includes(
        "static const int maxAdsPerDay = 5;"),
    existingDiamondAwardIsLocal:
      sources.diamondRewardPatch.includes(
        "SharedPreferences.getInstance()") &&
      sources.diamondRewardPatch.includes(
        "claimFuture = DedaDiamondsWallet.claimReward();"),
    separateTaskRewardIsPoints:
      sources.taskRewardPatch.includes(
        "DedaTaskEngine.claimTaskRewardedAdBonus(taskId)"),
    privateSsvNotExportedToCloudFunctions:
      !sources.functionsIndex.includes(
        "deda_jamal_stage22_admob_ssv_ecdsa_staged_no_deploy") &&
      !sources.functionsIndex.includes(
        "deda_jamal_stage24_offline_ssv_key") &&
      !sources.functionsIndex.includes(
        "deda_jamal_stage27_admob_signature_contract_audit"),
    unpatchedRawMainHasNoSsvIntegration:
      !sources.actualMainUnpatched.includes(
        "ServerSideVerificationOptions") &&
      !sources.actualMainUnpatched.includes("setServerSideOptions"),
  });
  return Object.freeze({
    stage:28,
    evidence:"read-only GitHub repository source inspection",
    config:{
      realAdUnitId:adUnit,
      realAdAppId:adApp,
      testingAdUnitDifferent:adUnit!==testAdUnit,
    },
    checks,
    missingChecks:Object.freeze(Object.keys(checks).filter(k=>!checks[k])),
    sourceEvidenceConsistent:Object.values(checks).every(Boolean),
    // These flags are not derivable from source; only a verified AdMob
    // console setup and real Google-signed callback would prove them.
    googleAdMobConsoleSSVEnabledVerified:false,
    officialGooglePublicKeySourceVerified:false,
    officialSignedCallbackTestPassed:false,
    issuedServerNonceAttachedToLiveSDKVerified:false,
    productionEndpointReady:false,
    previousLocalDiamondsMigrated:false,
    livePurchasesEnabled:false,
    productionCertified:false,
    note:"Neither source tests nor fake ECDSA signatures certify Google SSV",
  });
}
function assertStage28Preproduction(report){
  if(!report || !report.sourceEvidenceConsistent ||
      report.googleAdMobConsoleSSVEnabledVerified!==false ||
      report.officialGooglePublicKeySourceVerified!==false ||
      report.officialSignedCallbackTestPassed!==false ||
      report.issuedServerNonceAttachedToLiveSDKVerified!==false ||
      report.productionEndpointReady!==false ||
      report.previousLocalDiamondsMigrated!==false ||
      report.livePurchasesEnabled!==false ||
      report.productionCertified!==false){
    const err=new Error("ssv-real-google-origin-and-provenance-unverified");
    err.code="failed-precondition";throw err;
  }
  return "SOURCE_AUDIT_ONLY_NOT_GOOGLE_SSV_CERTIFICATION";
}
module.exports={loadRepoSources,detectSourceReadiness,assertStage28Preproduction};
