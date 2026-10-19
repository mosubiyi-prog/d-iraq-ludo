"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const {generateKeyPairSync,sign}=require("node:crypto");
const {verifyProviderSignedCallback}=
  require("../tools/deda_jamal_stage22_admob_ssv_ecdsa_staged_no_deploy_2026_10_19.js");
const {
  CONSOLE_SNAPSHOT,DEMO_EXPECTED,reviewConsoleVsCurrentSource,
  prohibitProductionRewardAction,
}=require("../tools/deda_jamal_stage29_console_reward_contract_vs_diamond_gate_2026_10_19.js");

const status=()=>reviewConsoleVsCurrentSource();
const invalid=(f)=>assert.throws(f,e=>e.code==="failed-precondition");
const {publicKey,privateKey}=generateKeyPairSync("ec",{
  namedCurve:"prime256v1",
});
function fakeSignedConsoleReward(){
  const fields=[
    "ad_unit="+encodeURIComponent(CONSOLE_SNAPSHOT.adUnitId),
    "custom_data="+"N".repeat(32),
    "reward_amount=5",
    "reward_item="+encodeURIComponent("DEDA Points"),
    "timestamp=1792414500000",
    "transaction_id=stage29_offline_ecdsa_only",
  ].join("&");
  return fields+"&signature="+
    sign("sha256",Buffer.from(fields),privateKey).toString("base64url")+
    "&key_id=12";
}

test("01 | user screenshot shows one named rewarded ad unit, reward 5 DEDA Points",()=>{
  assert.equal(CONSOLE_SNAPSHOT.adFormat,"Rewarded");
  assert.equal(CONSOLE_SNAPSHOT.adUnitName,"DEDA Rewarded +5 Points");
  assert.equal(CONSOLE_SNAPSHOT.rewardAmount,5);
  assert.equal(CONSOLE_SNAPSHOT.rewardItem,"DEDA Points");
});
test("02 | screenshot says no SSV callback URL configured",()=>{
  assert.equal(CONSOLE_SNAPSHOT.callbackUi,"No callback URL provided");
  assert.equal(CONSOLE_SNAPSHOT.ssvCallbackConfigured,false);
  assert.equal(status().googleCallbackOriginProven,false);
});
test("03 | observed console ad unit equals source real DEDA AdMob unit",()=>{
  assert.equal(status().mismatch.sameAdUnitAsStagedDemo,true);
  assert.equal(status().observedConsole.adUnitId,CONSOLE_SNAPSHOT.adUnitId);
});
test("04 | source Stage22 fake SSV expected 1 diamonds, not 5 DEDA Points",()=>{
  const out=status();
  assert.equal(DEMO_EXPECTED.rewardAmount,1);
  assert.equal(DEMO_EXPECTED.rewardItem,"diamonds");
  assert.equal(out.mismatch.recordedRewardAmountDiffersFromStage22Demo,true);
  assert.equal(out.mismatch.recordedRewardItemDiffersFromStage22Demo,true);
});
test("05 | legacy existing real phone still locally credits 3 diamonds",()=>{
  assert.equal(status().mismatch.historicClientAwardIsThreeDiamonds,true);
  assert.equal(status().currentAppRewardsMustRemainUnchanged,true);
});
test("06 | task ad +5 points kept separate from +3 diamonds",()=>{
  const out=status();
  assert.equal(out.mismatch.independentFivePointTaskRewardCodePresent,true);
  assert.equal(out.localTaskPointsPreserved,true);
  assert.equal(out.migrateOrConvertPointsToDiamonds,false);
});
test("07 | can't enable real Google SSV from an OFF setting or change AdMob automatically",()=>{
  const out=status();
  assert.equal(out.officialGoogleSSVVerified,false);
  assert.equal(out.createNewAdUnitAutomatically,false);
  assert.equal(out.modifyExistingRewardedUnitAutomatically,false);
  assert.equal(out.liveRewardGrantAllowed,false);
});
test("08 | original local 63 or large user diamond balances never rewritten",()=>{
  const out=status();
  assert.equal(out.oldLocalDiamondsPreserved,true);
  assert.equal(out.repriceOldBalances,false);
  assert.equal(out.liveDiamondCheckoutAllowed,false);
  assert.equal("newWalletBalance" in out,false);
});
test("09 | hard stop on a real 5 DEDA Points provider credit before verified callback",()=>{
  invalid(()=>prohibitProductionRewardAction("grant_points",status()));
});
test("10 | hard stop on treating 5 points as a 3-diamond payout",()=>{
  invalid(()=>prohibitProductionRewardAction("grant_diamonds",status()));
});
test("11 | can't spend 5k diamonds using unverified ad reward",()=>{
  invalid(()=>prohibitProductionRewardAction("spend_diamonds",status()));
});
test("12 | cannot claim provider-origin verification for local onUserEarnedReward",()=>{
  invalid(()=>prohibitProductionRewardAction(
    "assign_real_google_provenance",status()));
});
test("13 | cannot activate SSV without official Google spec and callback",()=>{
  invalid(()=>prohibitProductionRewardAction("enable_ssv",status()));
});
test("14 | malicious unknown reward operation is denied",()=>{
  invalid(()=>prohibitProductionRewardAction("import_every_old_wallet",status()));
});
test("15 | screenshot not sufficient to claim a callback became configured",()=>{
  invalid(()=>reviewConsoleVsCurrentSource({
    consoleSnapshot:{...CONSOLE_SNAPSHOT,ssvCallbackConfigured:true,
      callbackUi:"https://example.invalid/ssv"},
  }));
});
test("16 | tampering the old AdMob unit reward amount requires new owner screenshot",()=>{
  invalid(()=>reviewConsoleVsCurrentSource({
    consoleSnapshot:{...CONSOLE_SNAPSHOT,rewardAmount:3},
  }));
});
test("17 | ad unit ID changed in owner screenshot cannot be mixed with source",()=>{
  invalid(()=>reviewConsoleVsCurrentSource({
    consoleSnapshot:{...CONSOLE_SNAPSHOT,
      adUnitId:"ca-app-pub-2512641627784244/0000000000"},
  }));
});
test("18 | forged evidence source claiming signed Google success is denied",()=>{
  invalid(()=>reviewConsoleVsCurrentSource({
    consoleSnapshot:{...CONSOLE_SNAPSHOT,
      source:"OFFICIAL_GOOGLE_CALLBACK_CONFIRMED"},
  }));
});
test("19 | reward item containing space is rejected by current OFFLINE Stage22 parser",()=>{
  const pins={"12":publicKey.export({type:"spki",format:"pem"}).toString()};
  assert.equal(status().mismatch.currentStage22RewardItemParserNeedsReviewedAdaptation,
    true);
  assert.throws(()=>verifyProviderSignedCallback(
    fakeSignedConsoleReward(),pins),
    e=>e.code==="permission-denied" &&
      e.message==="signed-callback-content-malformed");
});
test("20 | no genuine Google private/public key or callback used in test",()=>{
  const out=status();
  assert.equal(out.googleCallbackOriginProven,false);
  assert.equal(out.liveRewardGrantAllowed,false);
  assert.equal(out.officialGoogleSSVVerified,false);
  assert.equal(out.status,
    "OWNER_OBSERVED_SETTINGS_NO_CALLBACK_REQUIRES_REAL_GOOGLE_SSV");
});
