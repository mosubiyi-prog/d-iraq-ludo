"use strict";
const test=require("node:test"),assert=require("node:assert/strict");
const {createRequire}=require("node:module");
const {resolve}=require("node:path");
const {readFileSync}=require("node:fs");
const {generateKeyPairSync,sign,createHash}=require("node:crypto");
assert.match(process.env.FIRESTORE_EMULATOR_HOST||"",
  /^(127[.]0[.]0[.]1|localhost):[0-9]+$/,"EMULATOR REQUIRED");
assert.equal(process.env.GCLOUD_PROJECT,
  "demo-deda-stage22-ssv-fakeprovider","FAKE PROVIDER ONLY");
const req=createRequire(resolve(__dirname,"../functions/package.json"));
const {initializeApp,deleteApp}=req("firebase-admin/app");
const {getFirestore}=req("firebase-admin/firestore");
const {initializeTestEnvironment,assertFails}=req("@firebase/rules-unit-testing");
const {doc,setDoc}=req("firebase/firestore");
const {getOfflineRewardStatus:check}=require(
  "../tools/deda_jamal_stage26_reward_receipt_status_readonly_2026_10_19.js");
const {createPendingRewardChallenge,acceptProviderVerifiedReward}=
  require("../tools/deda_jamal_stage22_admob_ssv_ecdsa_staged_no_deploy_2026_10_19.js");

const PROJECT="demo-deda-stage22-ssv-fakeprovider";
const CLOCK=Date.parse("2026-10-19T12:00:00Z");
const {publicKey,privateKey}=generateKeyPairSync("ec",{namedCurve:"prime256v1"});
const PINS={"17":publicKey.export({format:"pem",type:"spki"}).toString()};
const policy={
  verifiedForProduction:false,
  adUnitId:"ca-app-pub-2512641627784244/6037567292",
  expectedRewardItem:"diamonds",
  expectedRewardAmount:1,rewardDiamonds:3,
};
const A={uid:"stage26_auth_A",older:"stage26_original_A",
  accountKey:"stage26_person_A",original:"@DEDA-A1B2C3"};
const B={uid:"stage26_auth_B",older:"stage26_original_B",
  accountKey:"stage26_person_B",original:"@DEDA-D4E5F6"};
let db,env,app,serial=0;
function signed(nonce){
  const msg=[
    "ad_unit="+encodeURIComponent(policy.adUnitId),
    "custom_data="+encodeURIComponent(nonce),
    "reward_amount=1","reward_item=diamonds",
    "timestamp="+CLOCK,
    "transaction_id=stage26_signed_demo_tx_"+String(++serial).padStart(5,"0"),
  ].join("&");
  return msg+"&signature="+
    sign("sha256",Buffer.from(msg),privateKey).toString("base64url")+
    "&key_id=17";
}
async function seed(){
  await env.clearFirestore();
  const batch=db.batch();
  for(const u of [A,B]){
    batch.set(db.collection("users").doc(u.older),{accountKey:u.accountKey});
    batch.set(db.collection("users").doc(u.uid),{
      accountKey:u.accountKey,sharePersonalId:u.original,
      localDiamonds:63,points:665,level:2,
    });
    batch.set(db.collection("deda_sessions").doc(u.uid),{
      uid:u.uid,accountKey:u.accountKey,
    });
    batch.set(db.collection("deda_share_ids").doc(u.original),{
      kind:"personal",publicId:u.original,ownerUid:u.older,active:true,
    });
    batch.set(db.collection("deda_diamond_gift_balances").doc(u.original),{
      publicId:u.original,balance:u===A?11:15,
    });
  }
  await batch.commit();
}
async function start(person=A){
  return createPendingRewardChallenge(db,{
    authUid:person.uid,policy,trustedNowMs:CLOCK,
  });
}
async function status(person,nonce,time=CLOCK){
  return check(db,{uid:person.uid,customData:nonce,trustedNowMs:time});
}
async function callback(nonce){
  return acceptProviderVerifiedReward(db,{
    rawQuery:signed(nonce),pinnedProviderKeys:PINS,
    policy,trustedNowMs:CLOCK,
  });
}
async function balance(){
  return (await db.collection("deda_diamond_gift_balances")
    .doc(A.original).get()).data().balance;
}
test.before(async()=>{
  app=initializeApp({projectId:PROJECT},"stage26-receipt-readonly");
  db=getFirestore(app);
  env=await initializeTestEnvironment({projectId:PROJECT,firestore:{
    host:"127.0.0.1",
    port:Number(process.env.FIRESTORE_EMULATOR_HOST.split(":")[1]),
    rules:readFileSync(resolve(__dirname,"../firestore.rules"),"utf8"),
  }});
});
test.after(async()=>{
  if(env)await env.cleanup();
  if(app)await deleteApp(app);
});
test("pending challenge displays WAITING, NOT a paid reward or live Google proof",async()=>{
  await seed();
  const p=await start();
  const state=await status(A,p.customData);
  assert.equal(state.status,"awaiting_offline_demo_callback");
  assert.equal(state.demoReceiptDiamonds,0);
  assert.equal(state.officialGoogleAdMobSSVVerified,false);
  assert.equal(state.serverVerifiedPurchasableDiamonds,0);
  assert.equal(state.canPurchase,false);
  assert.equal(await balance(),11);
});
test("signed OFFLINE demo receipt displays recorded once but NOT official SSV",async()=>{
  await seed();
  const p=await start();
  assert.equal((await callback(p.customData)).diamondsAwarded,3);
  const s=await status(A,p.customData);
  assert.equal(s.status,"offline_demo_receipt_recorded");
  assert.equal(s.demoReceiptDiamonds,3);
  assert.equal(s.officialGoogleAdMobSSVVerified,false);
  assert.equal(s.historicalLocalAdsAutomaticallyMigrated,false);
  assert.equal(s.existingProfileBalanceOverridden,false);
  assert.equal(s.canPurchase,false);
  assert.equal(await balance(),14);
  const user=(await db.collection("users").doc(A.uid).get()).data();
  assert.equal(user.localDiamonds,63);
  assert.equal(user.points,665);
});
test("repeat status query causes ZERO wallet writes and no double credit",async()=>{
  await seed();
  const p=await start();
  await callback(p.customData);
  const before=await balance();
  for(let i=0;i<5;i++)
    assert.equal((await status(A,p.customData)).demoReceiptDiamonds,3);
  assert.equal(await balance(),before);
});
test("second account cannot poll another user's nonce regardless of local balance",async()=>{
  await seed();
  const p=await start();
  await assert.rejects(status(B,p.customData),
    e=>e.code==="permission-denied");
  await callback(p.customData);
  await assert.rejects(status(B,p.customData),
    e=>e.code==="permission-denied");
});
test("unrecognized nonce, wrong format or missing session cannot claim a receipt",async()=>{
  await seed();
  const p=await start();
  await assert.rejects(status(A,"Z".repeat(32)),
    e=>e.code==="permission-denied");
  await assert.rejects(status(A,"../forged"),
    e=>e.code==="invalid-argument");
  await db.collection("deda_sessions").doc(A.uid)
    .update({accountKey:"other_person"});
  await assert.rejects(status(A,p.customData),
    e=>e.code==="permission-denied");
});
test("expired pending challenge is display-only EXPIRED, cannot give 3",async()=>{
  await seed();
  const p=await start();
  const s=await status(A,p.customData,CLOCK+24*3600000+2000);
  assert.equal(s.status,"demo_challenge_expired");
  assert.equal(s.demoReceiptDiamonds,0);
  assert.equal(s.canPurchase,false);
  assert.equal(await balance(),11);
});
test("tampered receipt provenance blocks fake Google certainty or purchase",async()=>{
  await seed();
  const p=await start();
  await callback(p.customData);
  const q=(await db.collection("deda_stage22_ssv_pending")
    .doc(createHash("sha256").update(p.customData).digest("hex")).get()).data();
  const id=createHash("sha256").update(q.transactionId).digest("hex");
  await db.collection("deda_stage22_ssv_receipts").doc(id)
    .update({provenance:"GOOGLE_CONFIRMED_BUT_ACTUALLY_FAKE"});
  await assert.rejects(status(A,p.customData),
    e=>e.code==="failed-precondition");
});
test("wallet balance never returned by receipt status: 63 remains user's existing display",async()=>{
  await seed();
  const p=await start();
  const s=await status(A,p.customData);
  assert.deepEqual(Object.keys(s).sort(),[
    "status","demoOnly","officialGoogleAdMobSSVVerified",
    "serverVerifiedPurchasableDiamonds","demoReceiptDiamonds",
    "existingLocalAdBalancePreserved","existingProfileBalanceOverridden",
    "historicalLocalAdsAutomaticallyMigrated","canPurchase",
    "realRewardPaymentEnabled",
  ].sort());
  assert.equal(s.existingLocalAdBalancePreserved,true);
  assert.equal(s.existingProfileBalanceOverridden,false);
  assert.equal(s.canPurchase,false);
  assert.equal(await balance(),11);
});
test("client SDK denied writing fake receipts or editing server reward nonce",async()=>{
  await seed();
  const p=await start();
  const client=env.authenticatedContext(A.uid).firestore();
  await assertFails(setDoc(doc(client,"deda_stage22_ssv_receipts",
    createHash("sha256").update("fake").digest("hex")),{
    accountKey:A.accountKey,diamondsAwarded:9999,
  }));
  await assertFails(setDoc(doc(client,"deda_stage22_ssv_pending",
    createHash("sha256").update(p.customData).digest("hex")),{
    status:"claimed",accountKey:A.accountKey,
  }));
  assert.equal((await status(A,p.customData)).status,
    "awaiting_offline_demo_callback");
});
test("stage26 status is completely blocked outside exact emulator project",async()=>{
  await seed();
  const p=await start();
  const old=process.env.GCLOUD_PROJECT;
  try{
    process.env.GCLOUD_PROJECT="live-project-is-not-authorized";
    await assert.rejects(status(A,p.customData),
      e=>e.code==="unavailable");
  } finally {
    process.env.GCLOUD_PROJECT=old;
  }
});
