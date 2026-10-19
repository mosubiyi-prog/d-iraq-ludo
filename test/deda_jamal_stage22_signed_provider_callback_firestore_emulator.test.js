"use strict";
// STAGED OFFLINE-KEY SIGNING TESTS — never mistake generated EC signatures
// for verified Google AdMob Server-Side Verification callbacks.
const test=require("node:test");
const assert=require("node:assert/strict");
const {createRequire}=require("node:module");
const {resolve}=require("node:path");
const {readFileSync}=require("node:fs");
const {createHash,generateKeyPairSync,sign}=require("node:crypto");
assert.match(process.env.FIRESTORE_EMULATOR_HOST||"",
  /^(127\.0\.0\.1|localhost):[0-9]+$/,"EMULATOR REQUIRED");
const req=createRequire(resolve(__dirname,"../functions/package.json"));
const {initializeApp,deleteApp}=req("firebase-admin/app");
const {getFirestore}=req("firebase-admin/firestore");
const {initializeTestEnvironment,assertFails}=req("@firebase/rules-unit-testing");
const {doc,setDoc,updateDoc}=req("firebase/firestore");
const {
  verifyProviderSignedCallback,createPendingRewardChallenge,
  acceptProviderVerifiedReward,iraqDay,
}=require("../tools/deda_jamal_stage22_admob_ssv_ecdsa_staged_no_deploy_2026_10_19.js");

const {publicKey,privateKey}=generateKeyPairSync("ec",{
  namedCurve:"prime256v1",
});
const KEY_ID="31415";
const PUB=publicKey.export({format:"pem",type:"spki"}).toString();
const KEYS={ [KEY_ID]:PUB };
const POLICY={
  verifiedForProduction:false,
  adUnitId:"ca-app-pub-2512641627784244/6037567292",
  expectedRewardItem:"diamonds",
  expectedRewardAmount:1,
  rewardDiamonds:3,
};
const CLOCK=Date.parse("2026-10-19T09:50:00Z");
const A={uid:"ssv_new_user_A",older:"ssv_old_user_A",
  key:"ssv_acct_A1",original:"@DEDA-Z9Y8X7"};
const B={uid:"ssv_new_user_B",older:"ssv_old_user_B",
  key:"ssv_acct_B2",original:"@DEDA-X9Y8Z7"};
const sha=s=>createHash("sha256").update(s).digest("hex");
let app,db,env,serial=0;

async function seed(){
  await env.clearFirestore();
  const batch=db.batch();
  for(const u of [A,B]){
    batch.set(db.collection("users").doc(u.uid),{
      accountKey:u.key,sharePersonalId:u.original,
      localDiamonds:999999,points:444,level:12,
    });
    batch.set(db.collection("users").doc(u.older),{
      accountKey:u.key,
    });
    batch.set(db.collection("deda_sessions").doc(u.uid),{
      uid:u.uid,accountKey:u.key,
    });
    batch.set(db.collection("deda_share_ids").doc(u.original),{
      kind:"personal",active:true,publicId:u.original,
      ownerUid:u.older,
    });
    batch.set(db.collection("deda_diamond_gift_balances")
      .doc(u.original),{
      publicId:u.original,balance:u===A?100:15,
    });
  }
  batch.set(db.collection("deda_admin_diamond_wallets")
    .doc(A.uid),{balance:900000,adminUid:A.uid});
  batch.set(db.collection("deda_gm_personal_diamond_wallets")
    .doc(A.key),{balance:28000,accountKey:A.key});
  await batch.commit();
}
function signedQuery(nonce,{
  id="ssv_tx_"+String(++serial).padStart(10,"0"),
  timestamp=CLOCK,
  policy=POLICY,rewardAmount=policy.expectedRewardAmount,
  rewardItem=policy.expectedRewardItem,adUnit=policy.adUnitId,
  extra="",keyId=KEY_ID,signingKey=privateKey,
}={}){
  const msg=[
    "ad_unit="+encodeURIComponent(adUnit),
    "custom_data="+encodeURIComponent(nonce),
    "reward_amount="+rewardAmount,
    "reward_item="+encodeURIComponent(rewardItem),
    "timestamp="+timestamp,
    "transaction_id="+encodeURIComponent(id),
  ].join("&")+(extra ? "&"+extra:"");
  const signature=sign("sha256",Buffer.from(msg,"utf8"),signingKey)
    .toString("base64url");
  return msg+"&signature="+signature+"&key_id="+keyId;
}
async function challenge(u=A,now=CLOCK){
  return createPendingRewardChallenge(db,{
    authUid:u.uid,policy:POLICY,trustedNowMs:now,
  });
}
async function claim(rawQuery,now=CLOCK){
  return acceptProviderVerifiedReward(db,{
    rawQuery,pinnedProviderKeys:KEYS,policy:POLICY,trustedNowMs:now,
  });
}
async function wallet(u=A){
  return (await db.collection("deda_diamond_gift_balances")
    .doc(u.original).get()).data().balance;
}
test.before(async()=>{
  app=initializeApp({projectId:"demo-deda-stage22-ssv-fakeprovider"},
    "deda-stage22-ssv-isolated-ecdsa");
  db=getFirestore(app);
  env=await initializeTestEnvironment({
    projectId:"demo-deda-stage22-ssv-fakeprovider",
    firestore:{
      host:"127.0.0.1",
      port:Number(process.env.FIRESTORE_EMULATOR_HOST.split(":")[1]),
      rules:readFileSync(resolve(__dirname,"../firestore.rules"),"utf8"),
    },
  });
});
test.after(async()=>{
  if(env)await env.cleanup();
  if(app)await deleteApp(app);
});
test("pinned ECDSA P-256 SHA-256 verifies RAW bytes without exposing secret or account",()=>{
  const nonce="A".repeat(32);
  const q=signedQuery(nonce);
  const got=verifyProviderSignedCallback(q,KEYS);
  assert.equal(got.customData,nonce);
  assert.equal(got.rewardAmount,1);
  assert.equal(got.adUnitId,POLICY.adUnitId);
  assert.equal(got.verifiedProviderKeyId,KEY_ID);
  assert.ok(!q.includes(A.uid));
  assert.ok(!q.includes(A.key));
});
test("signed ECDSA callback + server nonce credits exactly 3 into verified existing personal wallet",async()=>{
  await seed();
  const started=await challenge();
  assert.equal(started.productionRewardActivation,false);
  assert.equal(started.customData.length,32);
  const q=signedQuery(started.customData);
  const beforeAdmin=(await db.collection("deda_admin_diamond_wallets")
    .doc(A.uid).get()).data();
  const beforeGM=(await db.collection("deda_gm_personal_diamond_wallets")
    .doc(A.key).get()).data();
  const out=await claim(q);
  assert.equal(out.outcome,"awarded");
  assert.equal(out.diamondsAwarded,3);
  assert.equal(await wallet(),103);
  assert.deepEqual((await db.collection("users").doc(A.uid).get())
    .data(),{
      accountKey:A.key,sharePersonalId:A.original,
      localDiamonds:999999,points:444,level:12,
    });
  assert.deepEqual((await db.collection("deda_admin_diamond_wallets")
    .doc(A.uid).get()).data(),beforeAdmin);
  assert.deepEqual((await db.collection("deda_gm_personal_diamond_wallets")
    .doc(A.key).get()).data(),beforeGM);
  const transactionId=new URLSearchParams(q).get("transaction_id");
  const receipt=(await db.collection("deda_stage22_ssv_receipts")
    .doc(sha(transactionId)).get()).data();
  assert.equal(receipt.provenance,
    "STAGE22_STAGED_ECDSA_OFFLINE_KEY_TEST_NOT_REAL_ADMOB");
  assert.equal(receipt.providerKeyId,KEY_ID);
});
test("same callback retry never doubles payout or changes daily count",async()=>{
  await seed();
  const q=signedQuery((await challenge()).customData);
  const first=await claim(q),again=await claim(q);
  assert.equal(first.diamondsAwarded,3);
  assert.equal(again.outcome,"already-recorded");
  assert.equal(again.diamondsAwarded,0);
  assert.equal(await wallet(),103);
});
test("10 simultaneous same signed callback attempts -> one credit of three",async()=>{
  await seed();
  const q=signedQuery((await challenge()).customData);
  const attempts=await Promise.allSettled(
    Array.from({length:10},()=>claim(q)));
  const actual=attempts.filter(x=>x.status==="fulfilled"&&
    x.value.outcome==="awarded");
  const repeat=attempts.filter(x=>x.status==="fulfilled"&&
    x.value.outcome==="already-recorded");
  assert.equal(actual.length,1);
  assert.equal(actual.length+repeat.length,10);
  assert.equal(await wallet(),103);
});
test("two different signed callbacks for same account cannot overwrite each other",async()=>{
  await seed();
  const first=await challenge(),second=await challenge();
  const results=await Promise.all([
    claim(signedQuery(first.customData)),
    claim(signedQuery(second.customData)),
  ]);
  assert.deepEqual(results.map(x=>x.diamondsAwarded),[3,3]);
  assert.equal(await wallet(),106);
});
test("nonce single-use even if attacker submits a different signed transaction",async()=>{
  await seed();
  const started=await challenge();
  await claim(signedQuery(started.customData,{id:"ssv_tx_unique_001"}));
  await assert.rejects(claim(signedQuery(started.customData,{
    id:"ssv_tx_unique_002"})),e=>e.code==="already-exists");
  assert.equal(await wallet(),103);
});
test("provider callback with no server-issued nonce cannot mint",async()=>{
  await seed();
  const q=signedQuery("N".repeat(32));
  await assert.rejects(claim(q),e=>e.code==="permission-denied");
  assert.equal(await wallet(),100);
});
test("tampered signed content, forged keys and unpinned key IDs are denied",async()=>{
  await seed();
  const started=await challenge();
  const q=signedQuery(started.customData);
  await assert.rejects(claim(q.replace("reward_amount=1","reward_amount=100")),
    e=>e.code==="permission-denied");
  await assert.rejects(claim(q.replace("key_id="+KEY_ID,"key_id=999999")),
    e=>e.code==="permission-denied");
  await assert.rejects(claim(q.replace("ad_unit=","ad_unit=malicious_")),
    e=>e.code==="permission-denied");
  const alien=generateKeyPairSync("ec",{namedCurve:"prime256v1"});
  await assert.rejects(claim(signedQuery(started.customData,{
    signingKey:alien.privateKey})),e=>e.code==="permission-denied");
  assert.equal(await wallet(),100);
});
test("duplicate signature/key_id and re-ordered signature metadata denied",async()=>{
  await seed();
  const started=await challenge();
  const q=signedQuery(started.customData);
  for(const invalid of [
    q+"&extra=evil",
    q+"&signature=AA",
    q+"&key_id="+KEY_ID,
    q.replace("&key_id="+KEY_ID,""),
    q.replace("ad_unit=","ad_unit=x&ad_unit="),
    "?"+q,
  ]){
    await assert.rejects(claim(invalid),
      e=>e.code==="permission-denied");
  }
  assert.equal(await wallet(),100);
});
test("wrong ad unit, amount or reward item even if signed by fake provider rejected",async()=>{
  await seed();
  const started=await challenge();
  for(const option of [
    {adUnit:"ca-app-pub-3940256099942544/5224354917"},
    {rewardAmount:2},
    {rewardItem:"coins"},
  ])await assert.rejects(claim(signedQuery(started.customData,option)),
    e=>e.code==="permission-denied");
  assert.equal(await wallet(),100);
});
test("5 ads per Baghdad day maximum regardless of 6th signed transaction",async()=>{
  await seed();
  for(let i=0;i<5;i++){
    const st=await challenge();
    assert.equal((await claim(signedQuery(st.customData))).diamondsAwarded,3);
  }
  const sixth=await challenge();
  await assert.rejects(claim(signedQuery(sixth.customData)),
    e=>e.code==="resource-exhausted");
  assert.equal(await wallet(),115);
  assert.equal((await db.collection("deda_stage22_ssv_receipts")
    .doc(sha("no_such_tx_001")).get()).exists,false);
});
test("expired challenge, signed timestamp before issuance, clock-skew denied",async()=>{
  await seed();
  const started=await challenge();
  await assert.rejects(claim(signedQuery(started.customData,{
    timestamp:CLOCK-4*60000})),e=>e.code==="permission-denied");
  await assert.rejects(claim(signedQuery(started.customData,{
    timestamp:CLOCK+4*60000})),e=>e.code==="permission-denied");
  await assert.rejects(claim(signedQuery(started.customData,{
    timestamp:CLOCK}),CLOCK+25*3600000),e=>e.code==="permission-denied");
  assert.equal(await wallet(),100);
});
test("cannot reuse signed callback for account B, no personal identifiers in callback",async()=>{
  await seed();
  const started=await challenge(A);
  const q=signedQuery(started.customData);
  assert.ok(!q.includes(A.key));
  assert.ok(!q.includes(A.original));
  await claim(q);
  assert.equal(await wallet(B),15);
});
test("tampered wallet or stolen share owner fails safely without receipt creation",async()=>{
  await seed();
  const started=await challenge();
  await db.collection("deda_diamond_gift_balances").doc(A.original)
    .update({publicId:B.original});
  await assert.rejects(claim(signedQuery(started.customData)),e=>
    e.code==="failed-precondition");
  assert.equal((await db.collection("deda_stage22_ssv_receipts")
    .doc(sha("ssv_tx_unknown")).get()).exists,false);
});
test("client cannot forge ECDSA event receipts, nonce or arbitrary wallet credit",async()=>{
  await seed();
  const client=env.authenticatedContext(A.uid).firestore();
  await assertFails(setDoc(doc(client,"deda_stage22_ssv_pending",
    sha("attacker")), {accountKey:A.key}));
  await assertFails(setDoc(doc(client,"deda_stage22_ssv_receipts",
    sha("attacker")), {transactionId:"attacker",diamondsAwarded:99999}));
  await assertFails(updateDoc(doc(client,"deda_diamond_gift_balances",
    A.original),{balance:99999999}));
  assert.equal(await wallet(),100);
});
test("same task/local diamonds, levels, gift pool and GM wallet unchanged on signed payout",async()=>{
  await seed();
  const userBefore=(await db.collection("users").doc(A.uid).get()).data();
  await claim(signedQuery((await challenge()).customData));
  const userAfter=(await db.collection("users").doc(A.uid).get()).data();
  assert.deepEqual(userAfter,userBefore);
  assert.equal((await db.collection("deda_admin_diamond_wallets")
    .doc(A.uid).get()).data().balance,900000);
  assert.equal((await db.collection("deda_gm_personal_diamond_wallets")
    .doc(A.key).get()).data().balance,28000);
});
