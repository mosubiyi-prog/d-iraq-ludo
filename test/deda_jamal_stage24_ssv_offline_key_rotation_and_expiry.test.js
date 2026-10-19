"use strict";
const test=require("node:test"),assert=require("node:assert/strict");
const {generateKeyPairSync,sign}=require("node:crypto");
const {validateSnapshot,verifyWithOfflinePinnedKeys}=
  require("../tools/deda_jamal_stage24_offline_ssv_key_freshness_no_deploy_2026_10_19.js");
const {publicKey,privateKey}=generateKeyPairSync("ec",{
  namedCurve:"prime256v1",
});
const fakePem=publicKey.export({format:"pem",type:"spki"}).toString();
const second=generateKeyPairSync("ec",{namedCurve:"prime256v1"});
const rotatedPem=second.publicKey.export({format:"pem",type:"spki"}).toString();
const now=Date.parse("2026-10-19T10:01:00Z");
const age=3600000;
const fakeOrigin="OFFLINE_GENERATED_FAKE_EC_KEYS_NOT_GOOGLE";
const prevHost=process.env.FIRESTORE_EMULATOR_HOST;
const prevProject=process.env.GCLOUD_PROJECT;
test.before(()=>{
  process.env.FIRESTORE_EMULATOR_HOST="127.0.0.1:8080";
  process.env.GCLOUD_PROJECT="demo-deda-stage22-ssv-fakeprovider";
});
test.after(()=>{
  if(prevHost===undefined)delete process.env.FIRESTORE_EMULATOR_HOST;
  else process.env.FIRESTORE_EMULATOR_HOST=prevHost;
  if(prevProject===undefined)delete process.env.GCLOUD_PROJECT;
  else process.env.GCLOUD_PROJECT=prevProject;
});
function source(keysById={"17":fakePem},attrs={}){
  return {
    origin:fakeOrigin,receivedAtMs:now-1000,
    expiresAtMs:now+age,keysById,...attrs,
  };
}
function signedQuery({
  signingKey=privateKey,keyId="17",rewardAmount="1",
}={}){
  const message=[
    "ad_unit=ca-app-pub-2512641627784244%2F6037567292",
    "custom_data="+"A".repeat(32),
    "reward_amount="+rewardAmount,
    "reward_item=diamonds",
    "timestamp="+String(now),
    "transaction_id=stg24_fake_provider_transaction",
  ].join("&");
  const sig=sign("sha256",Buffer.from(message,"utf8"),signingKey)
    .toString("base64url");
  return message+"&signature="+sig+"&key_id="+keyId;
}
test("approved OFFLINE fake P256 public snapshot validates with no production permission",()=>{
  const cache=validateSnapshot(source(),now);
  assert.equal(cache.deploymentPermitted,false);
  assert.equal(cache.googleKeyAuthenticityVerified,false);
  assert.equal(cache.origin,fakeOrigin);
  assert.equal(cache.keysById["17"],fakePem);
  assert.equal(Object.isFrozen(cache),true);
  assert.equal(Object.isFrozen(cache.keysById),true);
});
test("generated P256 signed raw callback verifies only while pinned and fresh",()=>{
  const cache=validateSnapshot(source(),now);
  const signed=verifyWithOfflinePinnedKeys(signedQuery(),cache,now);
  assert.equal(signed.rewardAmount,1);
  assert.equal(signed.verifiedProviderKeyId,"17");
  assert.equal(signed.customData,"A".repeat(32));
});
test("rotation accepts NEW pinned key and rejects removed OLD key ID",()=>{
  const rotated=validateSnapshot(source({"18":rotatedPem}),now);
  assert.equal(verifyWithOfflinePinnedKeys(signedQuery({
    signingKey:second.privateKey,keyId:"18",
  }),rotated,now).verifiedProviderKeyId,"18");
  assert.throws(()=>verifyWithOfflinePinnedKeys(
    signedQuery(),rotated,now),e=>e.code==="permission-denied");
});
test("pinned ID cannot be replaced with attacker-generated different public key",()=>{
  const wrong=validateSnapshot(source({"17":rotatedPem}),now);
  assert.throws(()=>verifyWithOfflinePinnedKeys(signedQuery(),wrong,now),
    e=>e.code==="permission-denied");
});
test("signed reward amount changed after signing cannot be accepted",()=>{
  const cache=validateSnapshot(source(),now);
  const good=signedQuery(),tampered=good.replace("reward_amount=1","reward_amount=999");
  assert.throws(()=>verifyWithOfflinePinnedKeys(tampered,cache,now),
    e=>e.code==="permission-denied");
});
test("expired/future/key-cache lifetime older than 24h fail closed",()=>{
  for(const bad of [
    source(undefined,{expiresAtMs:now-1}),
    source(undefined,{receivedAtMs:now-25*3600000}),
    source(undefined,{expiresAtMs:now+25*3600000}),
    source(undefined,{receivedAtMs:now+3*60000}),
  ])assert.throws(()=>validateSnapshot(bad,now),
    e=>e.code==="unavailable");
  const cache=validateSnapshot(source(),now);
  assert.throws(()=>verifyWithOfflinePinnedKeys(signedQuery(),cache,now+age),
    e=>e.code==="unavailable");
});
test("claim of Google origin cannot convert offline keys into authority",()=>{
  assert.throws(()=>validateSnapshot(
    source(undefined,{origin:"GOOGLE_PUBLIC_KEYS_VERIFIED"}),now),
  e=>e.code==="unavailable");
});
test("RSA, P384 and private PEM are not valid P256 signed public key material",()=>{
  const rsa=generateKeyPairSync("rsa",{modulusLength:2048});
  const p384=generateKeyPairSync("ec",{namedCurve:"secp384r1"});
  const bad=[
    rsa.publicKey.export({type:"spki",format:"pem"}).toString(),
    p384.publicKey.export({type:"spki",format:"pem"}).toString(),
    privateKey.export({type:"pkcs8",format:"pem"}).toString(),
  ];
  for(const pem of bad)assert.throws(()=>
    validateSnapshot(source({"17":pem}),now),e=>e.code==="unavailable");
});
test("duplicate P256 public key under multiple fake IDs denied",()=>{
  assert.throws(()=>validateSnapshot(source({
    "17":fakePem,"18":fakePem,
  }),now),e=>e.code==="unavailable");
});
test("bad/missing key IDs, empty lists and attacker-contaminated PEM refused",()=>{
  for(const keys of [
    {},
    {"test-key":fakePem},
    {"17":fakePem+"\nEVIL"},
    {"17":"not-a-key"},
  ])assert.throws(()=>validateSnapshot(source(keys),now),
    e=>e.code==="unavailable");
});
test("cache object forged by client without frozen/pinned reviewed key list refused",()=>{
  const obj=source();
  obj.issuedAt=obj.receivedAtMs;
  obj.deploymentPermitted=false;
  obj.googleKeyAuthenticityVerified=false;
  assert.throws(()=>verifyWithOfflinePinnedKeys(signedQuery(),obj,now),
    e=>e.code==="unavailable");
});
test("even valid offline EC signature cannot work in real Firebase project",()=>{
  const cache=validateSnapshot(source(),now);
  process.env.GCLOUD_PROJECT="some-live-firebase-project";
  try{
    assert.throws(()=>verifyWithOfflinePinnedKeys(signedQuery(),cache,now),
      e=>e.code==="unavailable");
    assert.throws(()=>validateSnapshot(source(),now),
      e=>e.code==="unavailable");
  }finally{
    process.env.GCLOUD_PROJECT="demo-deda-stage22-ssv-fakeprovider";
  }
});
