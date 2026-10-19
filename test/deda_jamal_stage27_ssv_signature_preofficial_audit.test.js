"use strict";

const test=require("node:test");
const assert=require("node:assert/strict");
const {generateKeyPairSync,sign}=require("node:crypto");
const {
  verifyProviderSignedCallback,
}=require("../tools/deda_jamal_stage22_admob_ssv_ecdsa_staged_no_deploy_2026_10_19.js");
const {
  inspectStage27SignatureContract,readRepoSources,assertNotProductionReady,
}=require("../tools/deda_jamal_stage27_admob_signature_contract_audit_no_deploy_2026_10_19.js");

const {privateKey,publicKey}=generateKeyPairSync("ec",{namedCurve:"prime256v1"});
const stranger=generateKeyPairSync("ec",{namedCurve:"prime256v1"});
const pins={"4321":publicKey.export({type:"spki",format:"pem"}).toString()};
const TIMESTAMP="1792414500000";
const NONCE="N".repeat(32);
const originalFields=()=>[
  "ad_unit=ca-app-pub-2512641627784244%2F6037567292",
  "custom_data="+NONCE,
  "reward_amount=1",
  "reward_item=diamonds",
  "timestamp="+TIMESTAMP,
  "transaction_id=offline_stage27_unsigned_0001",
];
function signed(fields=originalFields(),{
  key=privateKey,keyId="4321",signatureEncoding="base64url",
}={}){
  const message=fields.join("&");
  const sig=sign("sha256",Buffer.from(message,"utf8"),key)
    .toString(signatureEncoding);
  return message+"&signature="+sig+"&key_id="+keyId;
}
function denied(action,code="permission-denied"){
  assert.throws(action,e=>e && e.code===code);
}

test("01 | repo source audit reports all Stage22/24/26 offline guards present",()=>{
  const report=inspectStage27SignatureContract(readRepoSources());
  assert.deepEqual(report.missingSourceSafetyChecks,[]);
  assert.equal(report.sourceGuardConsistent,true);
  assert.equal(report.allowedToDeploy,false);
});
test("02 | locally signed EC SHA256 DER test vector works, is NOT Google proof",()=>{
  const observed=verifyProviderSignedCallback(signed(),pins);
  assert.equal(observed.customData,NONCE);
  assert.equal(observed.verifiedProviderKeyId,"4321");
  assert.equal(observed.rewardAmount,1);
  assert.equal(observed.transactionId,"offline_stage27_unsigned_0001");
});
test("03 | all changes of signed amount/ad unit/nonce/time/item/transaction fail",()=>{
  const good=signed();
  const tamper=[
    ["reward_amount=1","reward_amount=3"],
    ["6037567292","6037567293"],
    [NONCE,"M".repeat(32)],
    [TIMESTAMP,"1792414500001"],
    ["reward_item=diamonds","reward_item=gold"],
    ["offline_stage27_unsigned_0001","offline_stage27_unsigned_0002"],
  ];
  for(const [a,b] of tamper){
    assert.notEqual(a,b);
    denied(()=>verifyProviderSignedCallback(good.replace(a,b),pins));
  }
});
test("04 | reorder even one signed field after signing fails",()=>{
  const good=signed();
  const mutated=good.replace(
    "reward_amount=1&reward_item=diamonds",
    "reward_item=diamonds&reward_amount=1");
  denied(()=>verifyProviderSignedCallback(mutated,pins));
});
test("05 | alternative percent-encoding after signing fails",()=>{
  const good=signed();
  denied(()=>verifyProviderSignedCallback(
    good.replace("%2F","%2f"),pins));
});
test("06 | wrong signing private key cannot spoof pinned provider",()=>{
  denied(()=>verifyProviderSignedCallback(
    signed(originalFields(),{key:stranger.privateKey}),pins));
});
test("07 | unknown or unapproved key_id cannot verify",()=>{
  denied(()=>verifyProviderSignedCallback(
    signed(originalFields(),{keyId:"4322"}),pins));
});
test("08 | P256 signed query with EXTRA signed key is rejected",()=>{
  denied(()=>verifyProviderSignedCallback(signed([
    ...originalFields(),"arbitrary_payment_amount=1000000",
  ]),pins));
});
test("09 | two fully signed duplicate fields are rejected even with good ECDSA",()=>{
  denied(()=>verifyProviderSignedCallback(signed([
    ...originalFields(),"reward_amount=1000",
  ]),pins));
});
test("10 | callback cannot omit server opaque nonce even when signed",()=>{
  denied(()=>verifyProviderSignedCallback(
    signed(originalFields().filter(s=>!s.startsWith("custom_data="))),pins));
});
test("11 | correct signature cannot excuse too-short or malformed nonce",()=>{
  const fields=originalFields().map(s=>
    s.startsWith("custom_data=")?"custom_data=client_uid_123":s);
  denied(()=>verifyProviderSignedCallback(signed(fields),pins));
});
test("12 | correct signature cannot authorize invalid reward amount",()=>{
  for(const amount of ["0","-1","01","99999","nan"]){
    const fields=originalFields().map(s=>
      s.startsWith("reward_amount=")?"reward_amount="+amount:s);
    denied(()=>verifyProviderSignedCallback(signed(fields),pins));
  }
});
test("13 | correct signature with missing/unparseable timestamp is blocked",()=>{
  for(const time of ["0","abc","999999999999999999999","1"]){
    const fields=originalFields().map(s=>
      s.startsWith("timestamp=")?"timestamp="+time:s);
    denied(()=>verifyProviderSignedCallback(signed(fields),pins));
  }
});
test("14 | trailing unknown query, duplicate signature and missing final key denied",()=>{
  const good=signed();
  for(const changed of [
    good+"&pay=3",
    good+"&signature=another",
    good.replace("&key_id=4321",""),
    "?"+good,
    good+"&key_id=4321",
  ])denied(()=>verifyProviderSignedCallback(changed,pins));
});
test("15 | query CR/LF, fragments and raw HTML-like injection denied",()=>{
  const good=signed();
  for(const changed of [
    good+"#foo",good+"\n",good+"\r",
    good.replace("ad_unit=","ad_unit=<script>"),
  ])denied(()=>verifyProviderSignedCallback(changed,pins));
});
test("16 | oversized message and intentionally huge signatures denied",()=>{
  const good=signed();
  denied(()=>verifyProviderSignedCallback(good+"&x=".repeat(3000),pins));
  denied(()=>verifyProviderSignedCallback(
    good.replace(/&signature=[^&]+/,"&signature="+"A".repeat(1600)),pins));
});
test("17 | no, empty, private or attacker-controlled public keys cannot verify",()=>{
  const good=signed();
  denied(()=>verifyProviderSignedCallback(good,{}),"unavailable");
  denied(()=>verifyProviderSignedCallback(good,{"4321":"bogus"}),"unavailable");
  denied(()=>verifyProviderSignedCallback(good,{
    "4321":privateKey.export({type:"pkcs8",format:"pem"}).toString(),
  }),"unavailable");
});
test("18 | current code cannot claim official Google SSV or turn on purchases",()=>{
  const report=inspectStage27SignatureContract(readRepoSources());
  assert.equal(report.liveAdMobProviderVerified,false);
  assert.equal(report.realGoogleSSVIntegrationCertified,false);
  assert.equal(report.allowedToMintLiveDiamonds,false);
  assert.equal(report.realPurchaseEnabled,false);
  assert.equal(report.currentUserAdRewardsUnchanged,true);
  assert.deepEqual(Object.values(report.independentOfficialEvidence),
    Array(7).fill(false));
  assert.equal(assertNotProductionReady(report),
    "RELEASE_BLOCKED_OFFICIAL_GOOGLE_EVIDENCE_MISSING");
});
test("19 | fake external official verification claims cannot override blockers",()=>{
  const report=inspectStage27SignatureContract(readRepoSources());
  const untrusted={...report,allowedToDeploy:true};
  denied(()=>assertNotProductionReady(untrusted),"unavailable");
  const fakeGoogle={
    ...report,independentOfficialEvidence:{
      ...report.independentOfficialEvidence,
      officialGoogleAdMobSSVSpecChecked:true,
    },
  };
  denied(()=>assertNotProductionReady(fakeGoogle),"unavailable");
});
test("20 | audit detects accidental production export of demo callback",()=>{
  const original=readRepoSources();
  const changed={
    ...original,
    functionsIndex:original.functionsIndex+
      '\nconst unsafe=require("../tools/deda_jamal_stage22_admob_ssv_ecdsa");',
  };
  const report=inspectStage27SignatureContract(changed);
  assert.equal(report.sourceGuardConsistent,false);
  assert.ok(report.missingSourceSafetyChecks.includes(
    "noStage22LiveBackendExport"));
  assert.equal(report.allowedToDeploy,false);
});
test("21 | losing nonce or forced offline policy is visible in audit",()=>{
  const original=readRepoSources();
  const changed={...original,stage22:original.stage22
    .replace("unknown-or-expired-server-ad-challenge","challenge-accepted")
    .replace("policy.verifiedForProduction!==false","true===false")};
  const report=inspectStage27SignatureContract(changed);
  assert.ok(report.missingSourceSafetyChecks.includes(
    "callbackRequiresServerNonce"));
  assert.ok(report.missingSourceSafetyChecks.includes(
    "serverRewardPolicyForcedOff"));
  assert.equal(report.allowedToDeploy,false);
});
test("22 | historical profile balance cannot be inferred from signed test data",()=>{
  const report=inspectStage27SignatureContract(readRepoSources());
  assert.equal(report.independentOfficialEvidence
    .legacyDiamondProvenanceMigrationApproved,false);
  assert.equal("legacyBalance" in report,false);
  assert.equal("migratedDiamonds" in report,false);
});
