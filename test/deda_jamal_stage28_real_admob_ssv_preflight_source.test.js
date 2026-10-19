"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const {
  loadRepoSources,detectSourceReadiness,assertStage28Preproduction,
}=require("../tools/deda_jamal_stage28_real_admob_unit_and_legacy_ads_readonly_audit_2026_10_19.js");
const originals=loadRepoSources();
const audit=(mod={})=>detectSourceReadiness({...originals,...mod});
function throwsPreflight(fn){
  assert.throws(fn,e=>e.code==="failed-precondition");
}
test("01 | real AdMob Android app publisher equals real rewarded unit publisher",()=>{
  const result=audit();
  const x=result.config.realAdAppId.match(/^ca-app-pub-(\d+)~/);
  const y=result.config.realAdUnitId.match(/^ca-app-pub-(\d+)\//);
  assert.equal(x[1],y[1]);
  assert.equal(result.config.testingAdUnitDifferent,true);
});
test("02 | real ad unit used by synthetic stage22 test matches build patch",()=>{
  assert.equal(audit().checks.stagedTestAdUnitMatchesBuild,true);
});
test("03 | historical build injects real rewarded ad unit via staged patch",()=>{
  assert.equal(audit().checks.oldBuildActuallyAppliesRealId,true);
});
test("04 | existing old diamond reward is +3 with maximum five LOCAL daily claims",()=>{
  const a=audit();
  assert.equal(a.checks.diamondsAreThreePerAd,true);
  assert.equal(a.checks.diamondsCappedFivePerLocalDay,true);
});
test("05 | old diamond claim is callback/SharedPreferences, not Google SSV",()=>{
  const a=audit();
  assert.equal(a.checks.existingDiamondAwardIsLocal,true);
  assert.equal(a.googleAdMobConsoleSSVEnabledVerified,false);
});
test("06 | rewarded task ad awards points, never convert its points into 3 diamonds",()=>{
  assert.equal(audit().checks.separateTaskRewardIsPoints,true);
});
test("07 | official SSV backend remains completely unexported",()=>{
  assert.equal(audit().checks.privateSsvNotExportedToCloudFunctions,true);
  assert.equal(audit().productionEndpointReady,false);
});
test("08 | raw main.dart not final patched APK source and no server SSV injected",()=>{
  assert.equal(audit().checks.unpatchedRawMainHasNoSsvIntegration,true);
  assert.equal(audit().issuedServerNonceAttachedToLiveSDKVerified,false);
});
test("09 | missing official documentation/real callback means STOP-SHIP",()=>{
  const a=audit();
  assert.equal(a.sourceEvidenceConsistent,true);
  assert.equal(a.officialGooglePublicKeySourceVerified,false);
  assert.equal(a.officialSignedCallbackTestPassed,false);
  assert.equal(a.productionCertified,false);
  assert.equal(assertStage28Preproduction(a),
    "SOURCE_AUDIT_ONLY_NOT_GOOGLE_SSV_CERTIFICATION");
});
test("10 | unit changed in staging cannot silently pass as approved DEDA unit",()=>{
  const replaced=originals.stage22SyntheticVerifierTest.replace(
    /ca-app-pub-2512641627784244\/6037567292/g,
    "ca-app-pub-2512641627784244/0000000000");
  const a=audit({stage22SyntheticVerifierTest:replaced});
  assert.equal(a.checks.stagedTestAdUnitMatchesBuild,false);
  assert.equal(a.sourceEvidenceConsistent,false);
  throwsPreflight(()=>assertStage28Preproduction(a));
});
test("11 | old separate task points overwritten by diamonds must trigger audit alarm",()=>{
  const a=audit({taskRewardPatch:originals.taskRewardPatch.replace(
    "DedaTaskEngine.claimTaskRewardedAdBonus(taskId)",
    "DedaDiamondsWallet.claimReward()")});
  assert.equal(a.sourceEvidenceConsistent,false);
  assert.equal(a.checks.separateTaskRewardIsPoints,false);
});
test("12 | accidentally introducing staged verifier into production functions fails",()=>{
  const a=audit({functionsIndex:originals.functionsIndex+
    '\nrequire("../tools/deda_jamal_stage22_admob_ssv_ecdsa_staged_no_deploy");'});
  assert.equal(a.checks.privateSsvNotExportedToCloudFunctions,false);
  throwsPreflight(()=>assertStage28Preproduction(a));
});
test("13 | legacy diamond reward changed from +3 or cap 5 must be caught",()=>{
  const a=audit({diamondRewardPatch:originals.diamondRewardPatch
    .replace("static const int rewardPerAd = 3;","static const int rewardPerAd = 999;")
    .replace("static const int maxAdsPerDay = 5;","static const int maxAdsPerDay = 999;")});
  assert.equal(a.checks.diamondsAreThreePerAd,false);
  assert.equal(a.checks.diamondsCappedFivePerLocalDay,false);
});
test("14 | declaring fake Google evidence true must never satisfy stage28 preflight",()=>{
  const a=audit();
  throwsPreflight(()=>assertStage28Preproduction({
    ...a,officialSignedCallbackTestPassed:true,
  }));
  throwsPreflight(()=>assertStage28Preproduction({
    ...a,productionCertified:true,
  }));
});
test("15 | real rewarded unit tampered to another publisher aborts immediately",()=>{
  const wrong=originals.appIdPatch.replace(
    "REAL_REWARDED_ID = 'ca-app-pub-2512641627784244/",
    "REAL_REWARDED_ID = 'ca-app-pub-3940256099942544/");
  throwsPreflight(()=>audit({appIdPatch:wrong}));
});
test("16 | absent repository source data must fail rather than guessing config",()=>{
  throwsPreflight(()=>detectSourceReadiness({}));
});
